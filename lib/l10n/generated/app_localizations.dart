import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// English UI message used by ui/components/d_navigation_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Primary navigation'**
  String get primaryNavigation;

  /// English UI message used by ui/components/d_command.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Commands'**
  String get commands;

  /// English UI message used by ui/components/d_command.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Type a command or search...'**
  String get typeACommandOrSearch;

  /// English UI message used by ui/components/d_command.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search commands'**
  String get searchCommands;

  /// English UI message used by ui/components/d_command.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Command results'**
  String get commandResults;

  /// English UI message used by ui/components/d_command.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// English UI message used by ui/components/d_command.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Command Palette'**
  String get commandPalette;

  /// English UI message used by ui/components/d_command.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search for a command to run...'**
  String get searchForACommandToRun;

  /// English UI message used by ui/components/d_pull_to_refresh.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Pull to refresh'**
  String get pullToRefresh;

  /// English UI message used by ui/components/d_pull_to_refresh.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Release to refresh'**
  String get releaseToRefresh;

  /// English UI message used by ui/components/d_pull_to_refresh.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Refreshing'**
  String get refreshing;

  /// English UI message used by ui/components/d_pull_to_refresh.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// English UI message used by ui/components/d_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get loadingDbutton;

  /// English UI message used by ui/components/d_menubar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Menu bar'**
  String get menuBar;

  /// English UI message used by ui/components/d_resizable.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Resize panel'**
  String get resizePanel;

  /// English UI message used by ui/components/d_questionnaire.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// English UI message used by ui/components/d_questionnaire.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Questionnaire progress'**
  String get questionnaireProgress;

  /// English UI message used by ui/components/d_questionnaire.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Question {valueCurrent} of {valueTotal}'**
  String questionOf(String valueCurrent, String valueTotal);

  /// English UI message used by ui/components/d_questionnaire.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// English UI message used by ui/components/d_questionnaire.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// English UI message used by ui/components/d_questionnaire.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// English UI message used by ui/components/d_questionnaire.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// English UI message used by ui/components/d_data_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// English UI message used by ui/components/d_data_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Select all rows on this page'**
  String get selectAllRowsOnThisPage;

  /// English UI message used by ui/components/d_data_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No results.'**
  String get noResults;

  /// English UI message used by ui/components/d_data_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Resize {columnLabel} column'**
  String resizeColumn(String columnLabel);

  /// English UI message used by ui/components/d_data_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Select row {index}'**
  String selectRow(String index);

  /// English UI message used by ui/components/d_data_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Sort ascending'**
  String get sortAscending;

  /// English UI message used by ui/components/d_data_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Sort descending'**
  String get sortDescending;

  /// English UI message used by ui/components/d_data_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Hide column'**
  String get hideColumn;

  /// English UI message used by ui/components/d_data_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{title} column options'**
  String columnOptions(String title);

  /// English UI message used by ui/components/d_data_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{title}, sorted ascending'**
  String sortedAscending(String title);

  /// English UI message used by ui/components/d_data_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{title}, sorted descending'**
  String sortedDescending(String title);

  /// English UI message used by ui/components/d_data_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{title}, not sorted'**
  String notSorted(String title);

  /// English UI message used by ui/components/d_data_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get columns;

  /// English UI message used by ui/components/d_data_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Toggle columns'**
  String get toggleColumns;

  /// English UI message used by ui/components/d_data_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Filter…'**
  String get filter;

  /// English UI message used by ui/components/d_data_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Rows per page'**
  String get rowsPerPage;

  /// English UI message used by ui/components/d_data_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Table pagination'**
  String get tablePagination;

  /// English UI message used by ui/components/d_data_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Page {statePage} of {metricsPageCount}'**
  String pageOf(String statePage, String metricsPageCount);

  /// English UI message used by ui/components/d_color_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Recently used'**
  String get recentlyUsed;

  /// English UI message used by ui/components/d_color_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get messageDefault;

  /// English UI message used by ui/components/d_color_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Hue'**
  String get hue;

  /// English UI message used by ui/components/d_color_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Saturation'**
  String get saturation;

  /// English UI message used by ui/components/d_color_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get brightness;

  /// English UI message used by ui/components/d_color_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Left and right change hue. Up and down change lightness.'**
  String get leftAndRightChangeHueUpAndDownChangeLightness;

  /// English UI message used by ui/components/d_color_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Lighter'**
  String get lighter;

  /// English UI message used by ui/components/d_color_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Darker'**
  String get darker;

  /// English UI message used by ui/components/d_dialog.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dismiss dialog'**
  String get dismissDialog;

  /// English UI message used by ui/components/d_dialog.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// English UI message used by ui/components/d_popover.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get options;

  /// English UI message used by ui/components/d_kbd.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Ctrl'**
  String get ctrl;

  /// English UI message used by ui/components/d_kbd.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Control'**
  String get control;

  /// English UI message used by ui/components/d_kbd.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Alt'**
  String get alt;

  /// English UI message used by ui/components/d_kbd.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Option'**
  String get option;

  /// English UI message used by ui/components/d_kbd.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Shift'**
  String get shift;

  /// English UI message used by ui/components/d_kbd.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Meta'**
  String get meta;

  /// English UI message used by ui/components/d_kbd.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get command;

  /// English UI message used by ui/components/d_kbd.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter'**
  String get enter;

  /// English UI message used by ui/components/d_kbd.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Numpad Enter'**
  String get numpadEnter;

  /// English UI message used by ui/components/d_kbd.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Esc'**
  String get esc;

  /// English UI message used by ui/components/d_kbd.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Space'**
  String get space;

  /// English UI message used by ui/components/d_kbd.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Tab'**
  String get tab;

  /// English UI message used by ui/components/d_kbd.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Backspace'**
  String get backspace;

  /// English UI message used by ui/components/d_kbd.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// English UI message used by ui/components/d_kbd.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get key;

  /// English UI message used by ui/components/d_kbd.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Escape'**
  String get escape;

  /// English UI message used by ui/components/d_kbd.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Arrow Up'**
  String get arrowUp;

  /// English UI message used by ui/components/d_kbd.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Arrow Down'**
  String get arrowDown;

  /// English UI message used by ui/components/d_kbd.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Arrow Left'**
  String get arrowLeft;

  /// English UI message used by ui/components/d_kbd.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Arrow Right'**
  String get arrowRight;

  /// English UI message used by ui/components/d_kbd.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Question mark'**
  String get questionMark;

  /// English UI message used by ui/components/d_pagination.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Pagination'**
  String get pagination;

  /// English UI message used by ui/components/d_pagination.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Page {page}, current page'**
  String pageCurrentPage(String page);

  /// English UI message used by ui/components/d_pagination.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Go to page {page}'**
  String goToPage(String page);

  /// English UI message used by ui/components/d_pagination.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Go to previous page'**
  String get goToPreviousPage;

  /// English UI message used by ui/components/d_pagination.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Go to next page'**
  String get goToNextPage;

  /// English UI message used by ui/components/d_pagination.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Go to first page'**
  String get goToFirstPage;

  /// English UI message used by ui/components/d_pagination.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Go to last page'**
  String get goToLastPage;

  /// English UI message used by ui/components/d_pagination.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'More pages'**
  String get morePages;

  /// English UI message used by ui/components/d_pagination.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No pages, {pageSize} items per page'**
  String noPagesItemsPerPage(String pageSize);

  /// English UI message used by ui/components/d_pagination.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Page {page} of {pageCount}, {pageSize} items per page'**
  String pageOfItemsPerPage(String page, String pageCount, String pageSize);

  /// English UI message used by ui/components/d_alert_dialog.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Alert dialog'**
  String get alertDialog;

  /// English UI message used by ui/components/d_bubble.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Working'**
  String get working;

  /// English UI message used by ui/components/d_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get sending;

  /// English UI message used by ui/components/d_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get delivered;

  /// English UI message used by ui/components/d_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get read;

  /// English UI message used by ui/components/d_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Failed to send'**
  String get failedToSend;

  /// English UI message used by ui/components/d_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Message deleted'**
  String get messageDeleted;

  /// English UI message used by ui/components/d_mermaid_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get copyCode;

  /// English UI message used by ui/components/d_mermaid_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// English UI message used by ui/components/d_mermaid_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Copy failed'**
  String get copyFailed;

  /// English UI message used by ui/components/d_mermaid_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Mermaid chart'**
  String get mermaidChart;

  /// English UI message used by ui/components/d_mermaid_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Collapse chart editor'**
  String get collapseChartEditor;

  /// English UI message used by ui/components/d_mermaid_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Expand chart editor'**
  String get expandChartEditor;

  /// English UI message used by ui/components/d_mermaid_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Mermaid source code'**
  String get mermaidSourceCode;

  /// English UI message used by ui/components/d_select.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Select an option'**
  String get selectAnOption;

  /// English UI message used by ui/components/d_select.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Select options'**
  String get selectOptions;

  /// English UI message used by ui/components/d_select.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Scroll options up'**
  String get scrollOptionsUp;

  /// English UI message used by ui/components/d_select.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Scroll options down'**
  String get scrollOptionsDown;

  /// English UI message used by ui/components/d_message_inbox_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose inbox'**
  String get chooseInbox;

  /// English UI message used by ui/components/d_message_inbox_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search inboxes…'**
  String get searchInboxes;

  /// English UI message used by ui/components/d_message_inbox_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search inboxes'**
  String get searchInboxesDmessageinboxmenu;

  /// English UI message used by ui/components/d_message_inbox_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No inboxes found.'**
  String get noInboxesFound;

  /// English UI message used by ui/components/d_calendar_events.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **', Today'**
  String get today;

  /// English UI message used by ui/components/d_calendar_events.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get todayDcalendarevents;

  /// English UI message used by ui/components/d_date_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Pick a date'**
  String get pickADate;

  /// English UI message used by ui/components/d_date_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Select date'**
  String get selectDate;

  /// English UI message used by ui/components/d_date_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Date Picker Range'**
  String get datePickerRange;

  /// English UI message used by ui/components/d_date_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'June 01, 2025'**
  String get june012025;

  /// English UI message used by ui/components/d_date_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// English UI message used by ui/components/d_date_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid date'**
  String get enterAValidDate;

  /// English UI message used by ui/components/d_date_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get time;

  /// English UI message used by ui/components/d_date_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid time'**
  String get enterAValidTime;

  /// English UI message used by ui/components/d_drawer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dismiss drawer'**
  String get dismissDrawer;

  /// English UI message used by ui/components/d_embed.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open in browser'**
  String get openInBrowser;

  /// English UI message used by ui/components/d_embed.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Embed loading timed out'**
  String get embedLoadingTimedOut;

  /// English UI message used by ui/components/d_embed.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading {title}'**
  String loadingDembed(String title);

  /// English UI message used by ui/components/d_embed.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not load this embed.'**
  String get couldNotLoadThisEmbed;

  /// English UI message used by ui/components/d_embed.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// English UI message used by ui/components/d_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dismiss sheet'**
  String get dismissSheet;

  /// English UI message used by ui/components/d_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Sheet background'**
  String get sheetBackground;

  /// English UI message used by ui/components/d_carousel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Slide {index} of {count}'**
  String slideOf(String index, String count);

  /// English UI message used by ui/components/d_carousel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Previous slide'**
  String get previousSlide;

  /// English UI message used by ui/components/d_carousel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Next slide'**
  String get nextSlide;

  /// English UI message used by ui/components/d_questionnaire_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose an answer to continue.'**
  String get chooseAnAnswerToContinue;

  /// English UI message used by ui/components/d_questionnaire_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose an answer or skip this question.'**
  String get chooseAnAnswerOrSkipThisQuestion;

  /// English UI message used by ui/components/d_audio_player.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not play this audio.'**
  String get couldNotPlayThisAudio;

  /// English UI message used by ui/components/d_audio_player.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Audio position'**
  String get audioPosition;

  /// English UI message used by ui/components/d_audio_player.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Pause audio'**
  String get pauseAudio;

  /// English UI message used by ui/components/d_audio_player.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Play audio'**
  String get playAudio;

  /// English UI message used by ui/components/d_audio_player.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Retry audio'**
  String get retryAudio;

  /// English UI message used by ui/components/d_audio_player.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open audio'**
  String get openAudio;

  /// English UI message used by ui/components/d_toast.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// English UI message used by ui/components/d_toast.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Close toast'**
  String get closeToast;

  /// English UI message used by ui/components/d_toast.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Close notification'**
  String get closeNotification;

  /// English UI message used by ui/components/d_sidebar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Sidebar'**
  String get sidebar;

  /// English UI message used by ui/components/d_sidebar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Toggle Sidebar'**
  String get toggleSidebar;

  /// English UI message used by ui/components/d_code_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Code editor'**
  String get codeEditor;

  /// English UI message used by ui/components/d_mermaid.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Mermaid diagram'**
  String get mermaidDiagram;

  /// English UI message used by ui/components/d_mermaid.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Copy source'**
  String get copySource;

  /// English UI message used by ui/components/d_mermaid.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The diagram is empty.'**
  String get theDiagramIsEmpty;

  /// English UI message used by ui/components/d_mermaid.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The diagram exceeds the 50,000 character limit.'**
  String get theDiagramExceedsThe50000CharacterLimit;

  /// English UI message used by ui/components/d_mermaid.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Diagram rendering timed out.'**
  String get diagramRenderingTimedOut;

  /// English UI message used by ui/components/d_mermaid.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Diagram image is too large.'**
  String get diagramImageIsTooLarge;

  /// English UI message used by ui/components/d_mermaid.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid Mermaid syntax.'**
  String get invalidMermaidSyntax;

  /// English UI message used by ui/components/d_mermaid.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not read the rendered diagram.'**
  String get couldNotReadTheRenderedDiagram;

  /// English UI message used by ui/components/d_mermaid.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not load the diagram renderer.'**
  String get couldNotLoadTheDiagramRenderer;

  /// English UI message used by ui/components/d_mermaid.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not start the diagram renderer.'**
  String get couldNotStartTheDiagramRenderer;

  /// English UI message used by ui/components/d_mermaid.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Mermaid source'**
  String get mermaidSource;

  /// English UI message used by ui/components/d_mermaid.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t render diagram'**
  String get couldnTRenderDiagram;

  /// English UI message used by ui/components/d_mermaid.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Rendering diagram'**
  String get renderingDiagram;

  /// English UI message used by ui/components/d_mermaid.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'View source'**
  String get viewSource;

  /// English UI message used by ui/components/d_mermaid.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Expand diagram'**
  String get expandDiagram;

  /// English UI message used by ui/components/d_mermaid.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not display the diagram.'**
  String get couldNotDisplayTheDiagram;

  /// English UI message used by ui/components/d_mermaid.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get zoomOut;

  /// English UI message used by ui/components/d_mermaid.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get zoomIn;

  /// English UI message used by ui/components/d_mermaid.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Fit'**
  String get fit;

  /// English UI message used by ui/components/d_drag.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{label}. Drag to move or activate for actions.'**
  String dragToMoveOrActivateForActions(String label);

  /// English UI message used by ui/components/d_breadcrumb.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Breadcrumb'**
  String get breadcrumb;

  /// English UI message used by ui/components/d_input.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get chooseFile;

  /// English UI message used by ui/components/d_input.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No file chosen'**
  String get noFileChosen;

  /// English UI message used by ui/components/d_input.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not choose a file. Try again.'**
  String get couldNotChooseAFileTryAgain;

  /// English UI message used by ui/components/d_input.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choosing…'**
  String get choosing;

  /// English UI message used by ui/components/d_slider.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get value;

  /// English UI message used by ui/components/d_slider.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Value {i}'**
  String valueDslider(String i);

  /// English UI message used by ui/components/d_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get calendar;

  /// English UI message used by ui/components/d_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get previousMonth;

  /// English UI message used by ui/components/d_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get nextMonth;

  /// English UI message used by ui/components/d_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose month'**
  String get chooseMonth;

  /// English UI message used by ui/components/d_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose year'**
  String get chooseYear;

  /// English UI message used by ui/components/d_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get week;

  /// English UI message used by ui/components/d_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Booked'**
  String get booked;

  /// English UI message used by ui/components/d_chart.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No data'**
  String get noData;

  /// English UI message used by ui/components/d_chart.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No category selected'**
  String get noCategorySelected;

  /// English UI message used by ui/components/d_chart.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Use left and right arrow keys to inspect values'**
  String get useLeftAndRightArrowKeysToInspectValues;

  /// English UI message used by ui/components/d_message_scroller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get messages;

  /// English UI message used by ui/components/d_message_scroller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Scroll to end'**
  String get scrollToEnd;

  /// English UI message used by ui/components/d_message_scroller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Scroll to start'**
  String get scrollToStart;

  /// English UI message used by ui/components/d_combobox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Suggestions'**
  String get suggestions;

  /// English UI message used by ui/components/d_combobox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get clearSelection;

  /// English UI message used by ui/components/d_combobox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Close suggestions'**
  String get closeSuggestions;

  /// English UI message used by ui/components/d_combobox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open suggestions'**
  String get openSuggestions;

  /// English UI message used by ui/components/d_combobox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Press Delete or Backspace to remove'**
  String get pressDeleteOrBackspaceToRemove;

  /// English UI message used by ui/components/d_combobox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove {rootLabelForValue}'**
  String remove(String rootLabelForValue);

  /// English UI message used by plugins/prometheus_alert_receiver/alert_data.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Firing'**
  String get firing;

  /// English UI message used by plugins/prometheus_alert_receiver/alert_data.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Silenced'**
  String get silenced;

  /// English UI message used by plugins/prometheus_alert_receiver/alert_data.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Stale'**
  String get stale;

  /// English UI message used by plugins/prometheus_alert_receiver/alert_data.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// English UI message used by plugins/prometheus_alert_receiver/alert_data.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open Link'**
  String get openLink;

  /// English UI message used by plugins/prometheus_alert_receiver/alert_data.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get alerts;

  /// English UI message used by plugins/prometheus_alert_receiver/alert_tables.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get expand;

  /// English UI message used by plugins/prometheus_alert_receiver/alert_tables.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get collapse;

  /// English UI message used by plugins/prometheus_alert_receiver/alert_tables.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open Alertmanager'**
  String get openAlertmanager;

  /// English UI message used by plugins/prometheus_alert_receiver/alert_tables.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Alert'**
  String get alert;

  /// English UI message used by plugins/prometheus_alert_receiver/alert_tables.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Previously silenced on {formatAlertLastSuppressedAt}'**
  String previouslySilencedOn(String formatAlertLastSuppressedAt);

  /// English UI message used by plugins/prometheus_alert_receiver/alert_tables.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Previously silenced'**
  String get previouslySilenced;

  /// English UI message used by plugins/prometheus_alert_receiver/alert_tables.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Quote Alert'**
  String get quoteAlert;

  /// English UI message used by plugins/prometheus_alert_receiver/alert_tables.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unknown time'**
  String get unknownTime;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This channel can no longer be changed.'**
  String get thisChannelCanNoLongerBeChanged;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Only followed channels can be starred.'**
  String get onlyFollowedChannelsCanBeStarred;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Another channel change is still finishing.'**
  String get anotherChannelChangeIsStillFinishing;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reconnect this site to change the channel.'**
  String get reconnectThisSiteToChangeTheChannel;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose a channel notification setting to change.'**
  String get chooseAChannelNotificationSettingToChange;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Only followed channels have notification settings.'**
  String get onlyFollowedChannelsHaveNotificationSettings;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Another notification change is still finishing.'**
  String get anotherNotificationChangeIsStillFinishing;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reconnect this site to change channel notifications.'**
  String get reconnectThisSiteToChangeChannelNotifications;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This member list is no longer available.'**
  String get thisMemberListIsNoLongerAvailable;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Only followed channels show their members.'**
  String get onlyFollowedChannelsShowTheirMembers;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reconnect this site to see channel members.'**
  String get reconnectThisSiteToSeeChannelMembers;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load this channel\'\'s members.'**
  String get couldnTLoadThisChannelSMembers;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The channel directory is no longer available.'**
  String get theChannelDirectoryIsNoLongerAvailable;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reconnect this site to browse chat channels.'**
  String get reconnectThisSiteToBrowseChatChannels;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load chat channels.'**
  String get couldnTLoadChatChannels;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This channel cannot be edited.'**
  String get thisChannelCannotBeEdited;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The channel slug must be between 1 and 100 characters.'**
  String get theChannelSlugMustBeBetween1And100Characters;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The channel description cannot exceed 280 characters.'**
  String get theChannelDescriptionCannotExceed280Characters;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reconnect this site to edit the channel.'**
  String get reconnectThisSiteToEditTheChannel;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This channel’s status cannot be changed.'**
  String get thisChannelSStatusCannotBeChanged;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Direct messages cannot be joined from Browse Channels.'**
  String get directMessagesCannotBeJoinedFromBrowseChannels;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This channel cannot be joined.'**
  String get thisChannelCannotBeJoined;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not load pinned messages.'**
  String get couldNotLoadPinnedMessages;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This message can no longer be flagged.'**
  String get thisMessageCanNoLongerBeFlagged;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This flag reason is no longer available.'**
  String get thisFlagReasonIsNoLongerAvailable;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Your message must be between {minimum} and {postFlagTypeMaximumMessageLength} characters.'**
  String yourMessageMustBeBetweenAndCharacters(
    String minimum,
    String postFlagTypeMaximumMessageLength,
  );

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Another message change is still finishing.'**
  String get anotherMessageChangeIsStillFinishing;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{pinned, select, true{This message can no longer be pinned.} other{This message can no longer be unpinned.}}'**
  String thisMessageCanNoLongerBe(String pinned);

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Select at least one message.'**
  String get selectAtLeastOneMessage;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Select no more than {maximumBulkDeleteMessages} messages to delete.'**
  String selectNoMoreThanMessagesToDelete(String maximumBulkDeleteMessages);

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'One or more messages can no longer be deleted.'**
  String get oneOrMoreMessagesCanNoLongerBeDeleted;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'One or more messages can no longer be moved.'**
  String get oneOrMoreMessagesCanNoLongerBeMoved;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose another public channel.'**
  String get chooseAnotherPublicChannel;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The selected messages or destination changed.'**
  String get theSelectedMessagesOrDestinationChanged;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This message can no longer be deleted.'**
  String get thisMessageCanNoLongerBeDeleted;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This message can no longer be restored.'**
  String get thisMessageCanNoLongerBeRestored;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This message can no longer be rebuilt.'**
  String get thisMessageCanNoLongerBeRebuilt;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'One of those messages is no longer available.'**
  String get oneOfThoseMessagesIsNoLongerAvailable;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'That transcript is still being built.'**
  String get thatTranscriptIsStillBeingBuilt;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This message can no longer be edited.'**
  String get thisMessageCanNoLongerBeEdited;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'A message cannot be empty.'**
  String get aMessageCannotBeEmpty;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Messages can be at most {chatMessageMaximumEditLength} characters.'**
  String messagesCanBeAtMostCharacters(String chatMessageMaximumEditLength);

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Another edit is still finishing.'**
  String get anotherEditIsStillFinishing;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This message changed before the edit could be saved.'**
  String get thisMessageChangedBeforeTheEditCouldBeSaved;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not find out who reacted.'**
  String get couldNotFindOutWhoReacted;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You no longer have access to this channel.'**
  String get youNoLongerHaveAccessToThisChannel;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not load this site’s chat channels.'**
  String get couldNotLoadThisSiteSChatChannels;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not load your chat threads.'**
  String get couldNotLoadYourChatThreads;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not load this channel’s threads.'**
  String get couldNotLoadThisChannelSThreads;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'That message is unavailable. Showing the thread instead.'**
  String get thatMessageIsUnavailableShowingTheThreadInstead;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This thread is no longer available.'**
  String get thisThreadIsNoLongerAvailable;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not load this thread.'**
  String get couldNotLoadThisThread;

  /// English UI message used by plugins/chat/chat_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not load this channel.'**
  String get couldNotLoadThisChannel;

  /// English UI message used by plugins/chat/chat_header_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Exit chat'**
  String get exitChat;

  /// English UI message used by plugins/chat/chat_header_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{urgentCount, plural, =1{Chat, {urgentCount} urgent message} other{Chat, {urgentCount} urgent messages}}'**
  String chatUrgent(num urgentCount);

  /// English UI message used by plugins/chat/chat_header_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Chat, unread messages'**
  String get chatUnreadMessages;

  /// English UI message used by plugins/chat/chat_header_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chat;

  /// English UI message used by plugins/chat/chat_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Someone'**
  String get someone;

  /// English UI message used by plugins/chat/chat_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'mentioned you in {channel}'**
  String mentionedYouIn(String channel);

  /// English UI message used by plugins/chat/chat_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'sent a message in {channel}'**
  String sentAMessageIn(String channel);

  /// English UI message used by plugins/chat/chat_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'invited you to {channel}'**
  String invitedYouTo(String channel);

  /// English UI message used by plugins/chat/chat_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'quoted your chat message'**
  String get quotedYourChatMessage;

  /// English UI message used by plugins/chat/chat_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'There is a new reply in a thread you follow'**
  String get thereIsANewReplyInAThreadYouFollow;

  /// English UI message used by plugins/chat/chat_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'New chat notification'**
  String get newChatNotification;

  /// English UI message used by plugins/chat/chat_thread_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Thread pane width'**
  String get threadPaneWidth;

  /// English UI message used by plugins/chat/chat_thread_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No replies yet.'**
  String get noRepliesYet;

  /// English UI message used by plugins/chat/chat_thread_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Drop files to upload to this thread'**
  String get dropFilesToUploadToThisThread;

  /// English UI message used by plugins/chat/chat_thread_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// English UI message used by plugins/chat/chat_thread_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Thread'**
  String get thread;

  /// English UI message used by plugins/chat/chat_thread_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Close thread'**
  String get closeThread;

  /// English UI message used by plugins/chat/chat_thread_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get normal;

  /// English UI message used by plugins/chat/chat_thread_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Mentions only'**
  String get mentionsOnly;

  /// English UI message used by plugins/chat/chat_thread_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Tracking'**
  String get tracking;

  /// English UI message used by plugins/chat/chat_thread_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Mentions and unread reply count'**
  String get mentionsAndUnreadReplyCount;

  /// English UI message used by plugins/chat/chat_thread_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Watching'**
  String get watching;

  /// English UI message used by plugins/chat/chat_thread_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Every reply and unread count'**
  String get everyReplyAndUnreadCount;

  /// English UI message used by plugins/chat/chat_thread_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Thread notifications'**
  String get threadNotifications;

  /// English UI message used by plugins/chat/chat_thread_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Thread settings'**
  String get threadSettings;

  /// English UI message used by plugins/chat/chat_browse_skeleton.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading {pageName}'**
  String loadingChatbrowseskeleton(String pageName);

  /// English UI message used by plugins/chat/chat_browse_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Find a channel'**
  String get findAChannel;

  /// English UI message used by plugins/chat/chat_browse_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// English UI message used by plugins/chat/chat_browse_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Membership'**
  String get membership;

  /// English UI message used by plugins/chat/chat_browse_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// English UI message used by plugins/chat/chat_browse_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No matching channels loaded yet.'**
  String get noMatchingChannelsLoadedYet;

  /// English UI message used by plugins/chat/chat_browse_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No channels match these filters.'**
  String get noChannelsMatchTheseFilters;

  /// English UI message used by plugins/chat/chat_browse_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get loadMore;

  /// English UI message used by plugins/chat/chat_browse_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// English UI message used by plugins/chat/chat_browse_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// English UI message used by plugins/chat/chat_browse_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get closed;

  /// English UI message used by plugins/chat/chat_browse_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get archived;

  /// English UI message used by plugins/chat/chat_browse_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Joined'**
  String get joined;

  /// English UI message used by plugins/chat/chat_browse_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Not joined'**
  String get notJoined;

  /// English UI message used by plugins/chat/chat_browse_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Read only'**
  String get readOnly;

  /// English UI message used by plugins/chat/chat_browse_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// English UI message used by plugins/chat/chat_browse_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get join;

  /// English UI message used by plugins/chat/chat_browse_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get leave;

  /// English UI message used by plugins/chat/chat_browse_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Leaving…'**
  String get leaving;

  /// English UI message used by plugins/chat/chat_browse_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Joining…'**
  String get joining;

  /// English UI message used by plugins/chat/chat_browse_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open channel'**
  String get openChannel;

  /// English UI message used by plugins/chat/chat_browse_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Join channel'**
  String get joinChannel;

  /// English UI message used by plugins/chat/chat_browse_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open {channelTitle} menu'**
  String openMenu(String channelTitle);

  /// English UI message used by plugins/chat/chat_browse_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not open this channel.'**
  String get couldNotOpenThisChannel;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Select message from {messageAuthorDisplayName}'**
  String selectMessageFrom(String messageAuthorDisplayName);

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Link copied!'**
  String get linkCopied;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t copy link.'**
  String get couldnTCopyLink;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Message copied!'**
  String get messageCopied;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t copy message.'**
  String get couldnTCopyMessage;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'HTML rebuild queued.'**
  String get hTMLRebuildQueued;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Thanks for keeping our community civil!'**
  String get thanksForKeepingOurCommunityCivil;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Flag message'**
  String get flagMessage;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add reaction'**
  String get addReaction;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get reply;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'React'**
  String get react;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Bookmark'**
  String get bookmark;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit bookmark'**
  String get editBookmark;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpin;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get pin;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLink;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get copyText;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Flag'**
  String get flag;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Restore deleted message'**
  String get restoreDeletedMessage;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Rebuild HTML'**
  String get rebuildHTML;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Message actions'**
  String get messageActions;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'More message actions'**
  String get moreMessageActions;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Pinned chat message'**
  String get pinnedChatMessage;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Bookmarked chat message'**
  String get bookmarkedChatMessage;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Chat message bookmarked with a reminder'**
  String get chatMessageBookmarkedWithAReminder;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Failed to send: {messageSendError}'**
  String failedToSendChatmessagetile(String messageSendError);

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Retry after cooldown'**
  String get retryAfterCooldown;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'View profile for @{messageAuthorUsername}, {authorFlairLabel}'**
  String viewProfileFor(String messageAuthorUsername, String authorFlairLabel);

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{replyFlairNull, select, true{Jump to message from @{replyUsername}: {replyExcerpt}} other{Jump to message from @{replyUsername}, {replyFlairLabel}: {replyExcerpt}}}'**
  String jumpToMessageFrom(
    String replyFlairNull,
    String replyUsername,
    String replyExcerpt,
    String replyFlairLabel,
  );

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Original message'**
  String get originalMessage;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'remove your reaction'**
  String get removeYourReaction;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'add this reaction'**
  String get addThisReaction;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open thread with {replies}.'**
  String openThreadWith(String replies);

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **' Latest reply'**
  String get latestReply;

  /// English UI message used by plugins/chat/chat_user_avatar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get online;

  /// English UI message used by plugins/chat/chat_channel_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unmute channel'**
  String get unmuteChannel;

  /// English UI message used by plugins/chat/chat_channel_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Mute channel'**
  String get muteChannel;

  /// English UI message used by plugins/chat/chat_channel_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Channel settings'**
  String get channelSettings;

  /// English UI message used by plugins/chat/chat_channel_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove from starred channels'**
  String get removeFromStarredChannels;

  /// English UI message used by plugins/chat/chat_channel_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add to starred channels'**
  String get addToStarredChannels;

  /// English UI message used by plugins/chat/chat_channel_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Close channel'**
  String get closeChannel;

  /// English UI message used by plugins/chat/chat_channel_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Leave channel'**
  String get leaveChannel;

  /// English UI message used by plugins/chat/chat_channel_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get never;

  /// English UI message used by plugins/chat/chat_channel_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'All activity'**
  String get allActivity;

  /// English UI message used by plugins/chat/chat_bookmark.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'chat message'**
  String get chatMessageChatbookmark;

  /// English UI message used by plugins/chat/chat_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Folders cannot be uploaded here.'**
  String get foldersCannotBeUploadedHere;

  /// English UI message used by plugins/chat/chat_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// English UI message used by plugins/chat/chat_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// English UI message used by plugins/chat/chat_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t open the photo library.'**
  String get couldnTOpenThePhotoLibrary;

  /// English UI message used by plugins/chat/chat_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t open the file picker.'**
  String get couldnTOpenTheFilePicker;

  /// English UI message used by plugins/chat/chat_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You cannot send chat messages.'**
  String get youCannotSendChatMessages;

  /// English UI message used by plugins/chat/chat_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This chat is read-only.'**
  String get thisChatIsReadOnly;

  /// English UI message used by plugins/chat/chat_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Replying to @{replyUsername}'**
  String replyingTo(String replyUsername);

  /// English UI message used by plugins/chat/chat_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Cancel reply'**
  String get cancelReply;

  /// English UI message used by plugins/chat/chat_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Message chat'**
  String get messageChat;

  /// English UI message used by plugins/chat/chat_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Message {channelTitle}'**
  String message(String channelTitle);

  /// English UI message used by plugins/chat/chat_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Message #{channelTitle}'**
  String messageChatcomposer(String channelTitle);

  /// English UI message used by plugins/chat/chat_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get files;

  /// English UI message used by plugins/chat/chat_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Photo Library'**
  String get photoLibrary;

  /// English UI message used by plugins/chat/chat_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Insert GIF'**
  String get insertGIF;

  /// English UI message used by plugins/chat/chat_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Emoji'**
  String get emoji;

  /// English UI message used by plugins/chat/chat_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add to message'**
  String get addToMessage;

  /// English UI message used by plugins/chat/chat_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add emoji'**
  String get addEmoji;

  /// English UI message used by plugins/chat/chat_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Cancel edit'**
  String get cancelEdit;

  /// English UI message used by plugins/chat/chat_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Send message'**
  String get sendMessage;

  /// English UI message used by plugins/chat/chat_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Save edit'**
  String get saveEdit;

  /// English UI message used by plugins/chat/chat_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Join #{channelTitle} to start chatting'**
  String joinToStartChatting(String channelTitle);

  /// English UI message used by plugins/chat/chat_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You can’t join #{channelTitle}'**
  String youCanTJoin(String channelTitle);

  /// English UI message used by plugins/chat/chat_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You’ll be able to post and reply, and it’ll show up in your channel list.'**
  String get youLlBeAbleToPostAndReplyAndItLl;

  /// English UI message used by plugins/chat/chat_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This channel isn’t open to new members right now.'**
  String get thisChannelIsnTOpenToNewMembersRightNow;

  /// English UI message used by plugins/chat/chat_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Sent by'**
  String get sentBy;

  /// English UI message used by plugins/chat/chat_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get people;

  /// English UI message used by plugins/chat/chat_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Username or me'**
  String get usernameOrMe;

  /// English UI message used by plugins/chat/chat_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Find messages sent by one person.'**
  String get findMessagesSentByOnePerson;

  /// English UI message used by plugins/chat/chat_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Channel'**
  String get channel;

  /// English UI message used by plugins/chat/chat_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Where'**
  String get where;

  /// English UI message used by plugins/chat/chat_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Channel slug or ID'**
  String get channelSlugOrID;

  /// English UI message used by plugins/chat/chat_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search one channel available to your account.'**
  String get searchOneChannelAvailableToYourAccount;

  /// English UI message used by plugins/chat/chat_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Thread replies'**
  String get threadReplies;

  /// English UI message used by plugins/chat/chat_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get content;

  /// English UI message used by plugins/chat/chat_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Excluding replies still includes messages that started a thread.'**
  String get excludingRepliesStillIncludesMessagesThatStartedAThread;

  /// English UI message used by plugins/chat/chat_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Include thread replies'**
  String get includeThreadReplies;

  /// English UI message used by plugins/chat/chat_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Exclude thread replies'**
  String get excludeThreadReplies;

  /// English UI message used by plugins/chat/chat_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Most relevant'**
  String get mostRelevant;

  /// English UI message used by plugins/chat/chat_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Latest message'**
  String get latestMessage;

  /// English UI message used by plugins/chat/chat_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Chat search is unavailable.'**
  String get chatSearchIsUnavailable;

  /// English UI message used by plugins/chat/chat_channel_list_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get channels;

  /// English UI message used by plugins/chat/chat_channel_list_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Starred channels'**
  String get starredChannels;

  /// English UI message used by plugins/chat/chat_channel_list_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Direct messages'**
  String get directMessages;

  /// English UI message used by plugins/chat/chat_channel_list_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reapply filter: {label}'**
  String reapplyFilter(String label);

  /// English UI message used by plugins/chat/chat_channel_list_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Show all: {label}'**
  String showAll(String label);

  /// English UI message used by plugins/chat/chat_channel_list_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filterChatchannellistactions;

  /// English UI message used by plugins/chat/chat_channel_list_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sort;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dismiss start chatting'**
  String get dismissStartChatting;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Start chatting'**
  String get startChatting;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not search Chat.'**
  String get couldNotSearchChat;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This conversation is no longer available.'**
  String get thisConversationIsNoLongerAvailable;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not start this chat.'**
  String get couldNotStartThisChat;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'A group chat can include up to {maximumGroupMembers} people.'**
  String aGroupChatCanIncludeUpToPeople(String maximumGroupMembers);

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not create this group.'**
  String get couldNotCreateThisGroup;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Bring a few people into the conversation.'**
  String get bringAFewPeopleIntoTheConversation;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Pick up a conversation or find someone new.'**
  String get pickUpAConversationOrFindSomeoneNew;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'New group chat'**
  String get newGroupChat;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Close start chatting'**
  String get closeStartChatting;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Group name (optional)'**
  String get groupNameOptional;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Chat destinations'**
  String get chatDestinations;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search chat recipients'**
  String get searchChatRecipients;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search users or groups'**
  String get searchUsersOrGroups;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search users, groups, or channels'**
  String get searchUsersGroupsOrChannels;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Start group chat'**
  String get startGroupChat;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove {memberLabelMember}'**
  String removeChatnewdirectmessage(String memberLabelMember);

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{membersCount} of {maximumGroupMembers} people selected'**
  String ofPeopleSelected(String membersCount, String maximumGroupMembers);

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get groups;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Recent conversations'**
  String get recentConversations;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get conversations;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Chat recipients and conversations'**
  String get chatRecipientsAndConversations;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Opening conversation…'**
  String get openingConversation;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Searching…'**
  String get searching;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Try searching again.'**
  String get trySearchingAgain;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search for people or groups to add.'**
  String get searchForPeopleOrGroupsToAdd;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search for a user to start a direct message.'**
  String get searchForAUserToStartADirectMessage;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No matches found. Try another name or username.'**
  String get noMatchesFoundTryAnotherNameOrUsername;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Create a group chat'**
  String get createAGroupChat;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Chat is disabled for this user.'**
  String get chatIsDisabledForThisUser;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This group cannot be added to Chat.'**
  String get thisGroupCannotBeAddedToChat;

  /// English UI message used by plugins/chat/chat_new_direct_message.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Group member limit reached'**
  String get groupMemberLimitReached;

  /// English UI message used by plugins/chat/chat_bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Bookmark chat message'**
  String get bookmarkChatMessage;

  /// English UI message used by plugins/chat/chat_bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Chat message bookmark'**
  String get chatMessageBookmark;

  /// English UI message used by plugins/chat/chat_uploads.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open image: {uploadOriginalFilename}'**
  String openImage(String uploadOriginalFilename);

  /// English UI message used by plugins/chat/chat_uploads.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open attachment: {uploadOriginalFilename}'**
  String openAttachment(String uploadOriginalFilename);

  /// English UI message used by plugins/chat/chat_uploads.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open attachment: {uploadOriginalFilename}, {filesize}'**
  String openAttachmentChatuploads(
    String uploadOriginalFilename,
    String filesize,
  );

  /// English UI message used by plugins/chat/chat_channel_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Direct message'**
  String get directMessage;

  /// English UI message used by plugins/chat/chat_channel_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open {title} details'**
  String openDetails(String title);

  /// English UI message used by plugins/chat/chat_browse_navigation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Browse chats'**
  String get browseChats;

  /// English UI message used by plugins/chat/chat_browse_navigation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Browse channels'**
  String get browseChannels;

  /// English UI message used by plugins/chat/chat_browse_navigation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Browse threads'**
  String get browseThreads;

  /// English UI message used by plugins/chat/chat_browse_navigation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Browse chat'**
  String get browseChat;

  /// English UI message used by plugins/chat/chat_browse_navigation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get chats;

  /// English UI message used by plugins/chat/chat_browse_navigation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Threads'**
  String get threads;

  /// English UI message used by plugins/chat/chat_api_client.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Missing direct-message chat channel.'**
  String get missingDirectMessageChatChannel;

  /// English UI message used by plugins/chat/chat_api_client.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Missing chat channel.'**
  String get missingChatChannel;

  /// English UI message used by plugins/chat/chat_api_client.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Missing chat channel membership.'**
  String get missingChatChannelMembership;

  /// English UI message used by plugins/chat/chat_api_client.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Missing chat message move destination.'**
  String get missingChatMessageMoveDestination;

  /// English UI message used by plugins/chat/chat_api_client.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Missing chat quote markdown.'**
  String get missingChatQuoteMarkdown;

  /// English UI message used by plugins/chat/chat_api_client.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Missing chat thread membership.'**
  String get missingChatThreadMembership;

  /// English UI message used by plugins/chat/chat_api_client.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'at most'**
  String get atMost;

  /// English UI message used by plugins/chat/chat_api_client.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'between 1 and'**
  String get between1And;

  /// English UI message used by plugins/chat/chat_shell_service.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{authorSomeone} in chat'**
  String inChat(String authorSomeone);

  /// English UI message used by plugins/chat/chat_shell_service.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// English UI message used by plugins/chat/chat_shell_service.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The topic composer is no longer available here.'**
  String get theTopicComposerIsNoLongerAvailableHere;

  /// English UI message used by plugins/chat/chat_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Start a message'**
  String get startAMessage;

  /// English UI message used by plugins/chat/chat_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Chat channels are not available.'**
  String get chatChannelsAreNotAvailable;

  /// English UI message used by plugins/chat/chat_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Chat is not available.'**
  String get chatIsNotAvailable;

  /// English UI message used by plugins/chat/chat_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Threads are not available.'**
  String get threadsAreNotAvailable;

  /// English UI message used by plugins/chat/chat_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Chat threads are not available.'**
  String get chatThreadsAreNotAvailable;

  /// English UI message used by plugins/chat/chat_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Chat search is not available.'**
  String get chatSearchIsNotAvailable;

  /// English UI message used by plugins/chat/chat_channel_threads_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'There are no active threads in this channel.'**
  String get thereAreNoActiveThreadsInThisChannel;

  /// English UI message used by plugins/chat/chat_inbox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No unread conversations.'**
  String get noUnreadConversations;

  /// English UI message used by plugins/chat/chat_inbox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No conversations yet.'**
  String get noConversationsYet;

  /// English UI message used by plugins/chat/chat_inbox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You have not joined any channels yet.'**
  String get youHaveNotJoinedAnyChannelsYet;

  /// English UI message used by plugins/chat/chat_inbox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You have no direct messages yet.'**
  String get youHaveNoDirectMessagesYet;

  /// English UI message used by plugins/chat/chat_inbox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No voice rooms yet.'**
  String get noVoiceRoomsYet;

  /// English UI message used by plugins/chat/chat_inbox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get unread;

  /// English UI message used by plugins/chat/chat_inbox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recent;

  /// English UI message used by plugins/chat/chat_inbox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Chat activity'**
  String get chatActivity;

  /// English UI message used by plugins/chat/chat_inbox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Voice rooms'**
  String get voiceRooms;

  /// English UI message used by plugins/chat/chat_inbox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Conversation type'**
  String get conversationType;

  /// English UI message used by plugins/chat/chat_inbox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get browse;

  /// English UI message used by plugins/chat/chat_inbox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not load conversations'**
  String get couldNotLoadConversations;

  /// English UI message used by plugins/chat/chat_inbox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get noMessagesYet;

  /// English UI message used by plugins/chat/chat_inbox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unread conversation'**
  String get unreadConversation;

  /// English UI message used by plugins/chat/chat_inbox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading conversations'**
  String get loadingConversations;

  /// English UI message used by plugins/chat/chat_channel_list_preferences.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Active in the last 30 days'**
  String get activeInTheLast30Days;

  /// English UI message used by plugins/chat/chat_channel_list_preferences.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Mentions'**
  String get mentions;

  /// English UI message used by plugins/chat/chat_channel_list_preferences.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Alphabetical'**
  String get alphabetical;

  /// English UI message used by plugins/chat/chat_channel_list_preferences.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get recentActivity;

  /// English UI message used by plugins/chat/chat_channel_list_preferences.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get priority;

  /// English UI message used by plugins/chat/chat_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get messageNew;

  /// English UI message used by plugins/chat/chat_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'New message'**
  String get newMessage;

  /// English UI message used by plugins/chat/chat_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Starred'**
  String get starred;

  /// English UI message used by plugins/chat/chat_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No channels match this filter.'**
  String get noChannelsMatchThisFilter;

  /// English UI message used by plugins/chat/chat_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You have no starred channels.'**
  String get youHaveNoStarredChannels;

  /// English UI message used by plugins/chat/chat_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading chat channels'**
  String get loadingChatChannels;

  /// English UI message used by plugins/chat/chat_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{badgeCount} urgent notifications'**
  String urgentNotifications(String badgeCount);

  /// English UI message used by plugins/chat/chat_channel_status.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Closing the channel prevents non-staff users from sending new messages or editing existing messages.'**
  String get closingTheChannelPreventsNonStaffUsersFromSendingNewMessages;

  /// English UI message used by plugins/chat/chat_channel_status.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reopening the channel lets all members send messages and edit their existing messages.'**
  String get reopeningTheChannelLetsAllMembersSendMessagesAndEditTheir;

  /// English UI message used by plugins/chat/chat_pinned_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Pinned messages'**
  String get pinnedMessages;

  /// English UI message used by plugins/chat/chat_pinned_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Pinned by {by}'**
  String pinnedBy(String by);

  /// English UI message used by plugins/chat/chat_pinned_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Message by {messageAuthorDisplayName}'**
  String messageBy(String messageAuthorDisplayName);

  /// English UI message used by plugins/chat/chat_pinned_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading pinned messages'**
  String get loadingPinnedMessages;

  /// English UI message used by plugins/chat/chat_pinned_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Pinned message'**
  String get pinnedMessage;

  /// English UI message used by plugins/chat/chat_pinned_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unseen pinned messages'**
  String get unseenPinnedMessages;

  /// English UI message used by plugins/chat/chat_conversation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not load this conversation.'**
  String get couldNotLoadThisConversation;

  /// English UI message used by plugins/chat/chat_conversation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Message not sent.'**
  String get messageNotSent;

  /// English UI message used by plugins/chat/chat_search_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search messages across your Chat channels.'**
  String get searchMessagesAcrossYourChatChannels;

  /// English UI message used by plugins/chat/chat_search_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No chat messages found.'**
  String get noChatMessagesFound;

  /// English UI message used by plugins/chat/chat_search_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not open this chat message.'**
  String get couldNotOpenThisChatMessage;

  /// English UI message used by plugins/chat/chat_search_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Relevance'**
  String get relevance;

  /// English UI message used by plugins/chat/chat_search_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Best matching messages first'**
  String get bestMatchingMessagesFirst;

  /// English UI message used by plugins/chat/chat_search_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Latest'**
  String get latest;

  /// English UI message used by plugins/chat/chat_search_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Newest messages first'**
  String get newestMessagesFirst;

  /// English UI message used by plugins/chat/chat_search_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search messages'**
  String get searchMessages;

  /// English UI message used by plugins/chat/chat_search_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// English UI message used by plugins/chat/chat_search_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Sort search results'**
  String get sortSearchResults;

  /// English UI message used by plugins/chat/chat_search_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Sort search results by {label}'**
  String sortSearchResultsBy(String label);

  /// English UI message used by plugins/chat/chat_search_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'in thread {threadTitle}'**
  String inThread(String threadTitle);

  /// English UI message used by plugins/chat/chat_user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to this forum to see chat notifications.'**
  String get reconnectToThisForumToSeeChatNotifications;

  /// English UI message used by plugins/chat/chat_user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load chat notifications from this forum.'**
  String get couldnTLoadChatNotificationsFromThisForum;

  /// English UI message used by plugins/chat/chat_user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You don’t have any chat notifications yet.'**
  String get youDonTHaveAnyChatNotificationsYet;

  /// English UI message used by plugins/chat/chat_my_threads_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'All channels'**
  String get allChannels;

  /// English UI message used by plugins/chat/chat_my_threads_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No chat threads yet.'**
  String get noChatThreadsYet;

  /// English UI message used by plugins/chat/chat_my_threads_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No threads in this channel.'**
  String get noThreadsInThisChannel;

  /// English UI message used by plugins/chat/chat_my_threads_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No replies yet'**
  String get noRepliesYetChatmythreadsview;

  /// English UI message used by plugins/chat/chat_my_threads_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{channelNull, select, true{{unread, select, true{Open thread {title}, {replyCountLabelThreadReplyCount}, unread} other{Open thread {title}, {replyCountLabelThreadReplyCount}}}} other{{unread, select, true{Open thread {title} in {channelTitle}, {replyCountLabelThreadReplyCount}, unread} other{Open thread {title} in {channelTitle}, {replyCountLabelThreadReplyCount}}}}}'**
  String openThread(
    String channelNull,
    String unread,
    String title,
    String replyCountLabelThreadReplyCount,
    String channelTitle,
  );

  /// English UI message used by plugins/chat/chat_my_threads_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not open this chat thread.'**
  String get couldNotOpenThisChatThread;

  /// English UI message used by plugins/chat/chat_my_threads_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open thread {title}'**
  String openThreadChatmythreadsview(String title);

  /// English UI message used by plugins/chat/chat_my_threads_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Latest reply'**
  String get latestReplyChatmythreadsview;

  /// English UI message used by plugins/chat/chat_preferences.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Show separate sidebar modes for forum and chat'**
  String get showSeparateSidebarModesForForumAndChat;

  /// English UI message used by plugins/chat/chat_preferences.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Always'**
  String get always;

  /// English UI message used by plugins/chat/chat_preferences.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'When chat is in fullscreen'**
  String get whenChatIsInFullscreen;

  /// English UI message used by plugins/chat/chat_channel_list_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not save channel preferences. Try again.'**
  String get couldNotSaveChannelPreferencesTryAgain;

  /// English UI message used by plugins/chat/chat_message_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Attachment'**
  String get attachment;

  /// English UI message used by plugins/chat/chat_thread_settings.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not save the thread title. Try again.'**
  String get couldNotSaveTheThreadTitleTryAgain;

  /// English UI message used by plugins/chat/chat_thread_settings.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// English UI message used by plugins/chat/chat_thread_settings.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Give this thread a title'**
  String get giveThisThreadATitle;

  /// English UI message used by plugins/chat/chat_thread_settings.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You can no longer edit this thread title.'**
  String get youCanNoLongerEditThisThreadTitle;

  /// English UI message used by plugins/chat/chat_channel_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No messages here yet.'**
  String get noMessagesHereYet;

  /// English UI message used by plugins/chat/chat_channel_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Drop files to upload to #{channelTitleChat}'**
  String dropFilesToUploadTo(String channelTitleChat);

  /// English UI message used by plugins/chat/chat_channel_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not start this thread. Try again.'**
  String get couldNotStartThisThreadTryAgain;

  /// English UI message used by plugins/chat/chat_channel_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Messages copied!'**
  String get messagesCopied;

  /// English UI message used by plugins/chat/chat_channel_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t copy messages.'**
  String get couldnTCopyMessages;

  /// English UI message used by plugins/chat/chat_channel_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Move messages'**
  String get moveMessages;

  /// English UI message used by plugins/chat/chat_channel_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Move {count} selected message to:} other{Move {count} selected messages to:}}'**
  String moveSelectedTo(num count);

  /// English UI message used by plugins/chat/chat_channel_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Destination channel'**
  String get destinationChannel;

  /// English UI message used by plugins/chat/chat_channel_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get move;

  /// English UI message used by plugins/chat/chat_channel_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Delete selected messages?'**
  String get deleteSelectedMessages;

  /// English UI message used by plugins/chat/chat_channel_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Are you sure you want to delete {count} message?} other{Are you sure you want to delete {count} messages?}}'**
  String areYouSureYouWantToDelete(num count);

  /// English UI message used by plugins/chat/chat_channel_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Messages deleted.'**
  String get messagesDeleted;

  /// English UI message used by plugins/chat/chat_channel_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Quote selected messages'**
  String get quoteSelectedMessages;

  /// English UI message used by plugins/chat/chat_channel_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// English UI message used by plugins/chat/chat_channel_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Move selected messages to another channel'**
  String get moveSelectedMessagesToAnotherChannel;

  /// English UI message used by plugins/chat/chat_channel_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Select no more than {chatControllerMaximumBulkDeleteMessages} messages'**
  String selectNoMoreThanMessages(
    String chatControllerMaximumBulkDeleteMessages,
  );

  /// English UI message used by plugins/chat/chat_channel_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Delete selected messages'**
  String get deleteSelectedMessagesChatchannelview;

  /// English UI message used by plugins/chat/chat_channel_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Cancel selection'**
  String get cancelSelection;

  /// English UI message used by plugins/chat/chat_channel_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Jump to latest messages, {pendingCount} new'**
  String jumpToLatestMessagesNew(String pendingCount);

  /// English UI message used by plugins/chat/chat_channel_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Jump to latest messages'**
  String get jumpToLatestMessages;

  /// English UI message used by plugins/chat/chat_channel_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'A message was deleted. [view]'**
  String get aMessageWasDeletedView;

  /// English UI message used by plugins/chat/chat_channel_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{messageIdsLength} messages were deleted. [view all]'**
  String messagesWereDeletedViewAll(String messageIdsLength);

  /// English UI message used by plugins/chat/chat_channel_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading newer messages'**
  String get loadingNewerMessages;

  /// English UI message used by plugins/chat/chat_channel_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading older messages'**
  String get loadingOlderMessages;

  /// English UI message used by plugins/chat/chat_channel_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading chat channel'**
  String get loadingChatChannel;

  /// English UI message used by plugins/chat/chat_channel_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit channel details'**
  String get editChannelDetails;

  /// English UI message used by plugins/chat/chat_channel_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// English UI message used by plugins/chat/chat_channel_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Slug'**
  String get slug;

  /// English UI message used by plugins/chat/chat_channel_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Used in the channel URL'**
  String get usedInTheChannelURL;

  /// English UI message used by plugins/chat/chat_channel_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// English UI message used by plugins/chat/chat_search_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search terms must be at most {maximumQueryLength} characters.'**
  String searchTermsMustBeAtMostCharacters(String maximumQueryLength);

  /// English UI message used by plugins/chat/chat_search_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not load more chat results.'**
  String get couldNotLoadMoreChatResults;

  /// English UI message used by plugins/chat/chat_search_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not search Chat. Try again.'**
  String get couldNotSearchChatTryAgain;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This channel is no longer available.'**
  String get thisChannelIsNoLongerAvailable;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Members ({channelMembershipsCount})'**
  String members(String channelMembershipsCount);

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get membersChatchannelinfoview;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Your notifications'**
  String get yourNotifications;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Hide unread indicators and stop channel notifications.'**
  String get hideUnreadIndicatorsAndStopChannelNotifications;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Push notifications'**
  String get pushNotifications;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose which activity should reach this device.'**
  String get chooseWhichActivityShouldReachThisDevice;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Conversation'**
  String get conversation;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Threaded replies'**
  String get threadedReplies;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Replies open as separate conversations alongside the main channel.'**
  String get repliesOpenAsSeparateConversationsAlongsideTheMainChannel;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enable threads'**
  String get enableThreads;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Channel information'**
  String get channelInformation;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Controls visibility and membership rules.'**
  String get controlsVisibilityAndMembershipRules;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Message history'**
  String get messageHistory;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Messages are removed after the retention period.'**
  String get messagesAreRemovedAfterTheRetentionPeriod;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Channel management'**
  String get channelManagement;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Channel is closed.'**
  String get channelIsClosed;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Channel is open.'**
  String get channelIsOpen;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Opening lets members post in this channel again.'**
  String get openingLetsMembersPostInThisChannelAgain;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Closing prevents non-staff members from posting.'**
  String get closingPreventsNonStaffMembersFromPosting;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Leave this channel'**
  String get leaveThisChannel;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove {channelTitle} from your sidebar and stop following its conversations.'**
  String removeFromYourSidebarAndStopFollowingItsConversations(
    String channelTitle,
  );

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Forever'**
  String get forever;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Tell people what this channel is about.'**
  String get tellPeopleWhatThisChannelIsAbout;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit details'**
  String get editDetails;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Filter members'**
  String get filterMembers;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No members.'**
  String get noMembers;

  /// English UI message used by plugins/chat/chat_channel_info_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No members found.'**
  String get noMembersFound;

  /// English UI message used by plugins/discourse_placeholder/placeholder_store.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid placeholder store'**
  String get invalidPlaceholderStore;

  /// English UI message used by plugins/discourse_placeholder/discourse_placeholder_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Select a value'**
  String get selectAValue;

  /// English UI message used by plugins/reactions/reaction_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove your {mine} reaction'**
  String removeYourReactionReactionpicker(String mine);

  /// English UI message used by plugins/reactions/reaction_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose a reaction'**
  String get chooseAReaction;

  /// English UI message used by plugins/reactions/reaction_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'choose a reaction'**
  String get chooseAReactionReactionpicker;

  /// English UI message used by plugins/reactions/reaction_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Still finding out which reactions this site allows.'**
  String get stillFindingOutWhichReactionsThisSiteAllows;

  /// English UI message used by plugins/reactions/reaction_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'More emojis'**
  String get moreEmojis;

  /// English UI message used by plugins/reactions/reactions_row.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{countLabelCountReaction}. Show all reactions'**
  String showAllReactions(String countLabelCountReaction);

  /// English UI message used by plugins/reactions/reactions_row.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Show all reactions'**
  String get showAllReactionsReactionsrow;

  /// English UI message used by plugins/reactions/reactions_row.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Post reactions'**
  String get postReactions;

  /// English UI message used by plugins/reactions/reactions_row.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reactions'**
  String get reactions;

  /// English UI message used by plugins/reactions/reactions_row.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'change your reaction to {reaction}'**
  String changeYourReactionTo(String reaction);

  /// English UI message used by plugins/reactions/reaction.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reaction({id}, count: {count}, canUndo: {canUndo})'**
  String reactionCountCanUndo(String id, String count, String canUndo);

  /// English UI message used by plugins/reactions/reaction.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reactions({entries}, mine: {mine}, users: {userCount})'**
  String reactionsMineUsers(String entries, String mine, String userCount);

  /// English UI message used by plugins/reactions/reactions_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'React to this post'**
  String get reactToThisPost;

  /// English UI message used by plugins/reactions/reactions_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'a topic'**
  String get aTopic;

  /// English UI message used by plugins/reactions/reactions_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'reacted to {count} of your posts'**
  String reactedToOfYourPosts(String count);

  /// English UI message used by plugins/reactions/reactions_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'reacted to your posts'**
  String get reactedToYourPosts;

  /// English UI message used by plugins/reactions/reactions_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'reacted to your post in {title}'**
  String reactedToYourPostIn(String title);

  /// English UI message used by plugins/topic_voting/topic_voting_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic votes'**
  String get topicVotes;

  /// English UI message used by plugins/topic_voting/topic_voting_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Extensions'**
  String get extensions;

  /// English UI message used by plugins/topic_voting/topic_voting_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'at least'**
  String get atLeast;

  /// English UI message used by plugins/topic_voting/topic_voting_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Match the number of votes on a topic.'**
  String get matchTheNumberOfVotesOnATopic;

  /// English UI message used by plugins/topic_voting/topic_voting_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Most votes'**
  String get mostVotes;

  /// English UI message used by plugins/discourse_mermaid/mermaid_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Mermaid chart editor'**
  String get mermaidChartEditor;

  /// English UI message used by plugins/discourse_lazy_videos/lazy_youtube.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'YouTube playlist'**
  String get youTubePlaylist;

  /// English UI message used by plugins/discourse_lazy_videos/lazy_youtube.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'YouTube video'**
  String get youTubeVideo;

  /// English UI message used by plugins/gifs/gifs_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search GIFs'**
  String get searchGIFs;

  /// English UI message used by plugins/gifs/gifs_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The composer changed while the GIF picker was open. Nothing was changed.'**
  String get theComposerChangedWhileTheGIFPickerWasOpenNothingWas;

  /// English UI message used by plugins/gifs/gif_picker_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Connect to this site before searching for GIFs.'**
  String get connectToThisSiteBeforeSearchingForGIFs;

  /// English UI message used by plugins/gifs/gif_picker_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'That GIF search is too long.'**
  String get thatGIFSearchIsTooLong;

  /// English UI message used by plugins/gifs/gif_picker_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'GIF search is not configured for this site, or its API key is invalid.'**
  String get gIFSearchIsNotConfiguredForThisSiteOrItsAPI;

  /// English UI message used by plugins/gifs/gif_picker_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'GIF search is not enabled for this site.'**
  String get gIFSearchIsNotEnabledForThisSite;

  /// English UI message used by plugins/gifs/gif_picker_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Too many GIF searches. Try again in a moment.'**
  String get tooManyGIFSearchesTryAgainInAMoment;

  /// English UI message used by plugins/gifs/gif_picker_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load GIFs. Check the connection and try again.'**
  String get couldnTLoadGIFsCheckTheConnectionAndTryAgain;

  /// English UI message used by plugins/gifs/gif_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Browse categories'**
  String get browseCategories;

  /// English UI message used by plugins/gifs/gif_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Type at least 3 characters to search for a GIF.'**
  String get typeAtLeast3CharactersToSearchForAGIF;

  /// English UI message used by plugins/gifs/gif_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No GIFs found.'**
  String get noGIFsFound;

  /// English UI message used by plugins/gifs/gif_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose GIF'**
  String get chooseGIF;

  /// English UI message used by plugins/gifs/gif_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose {resultTitle} GIF'**
  String chooseGIFGifpicker(String resultTitle);

  /// English UI message used by plugins/gifs/gif_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search {categoryTitle} GIFs'**
  String searchGIFsGifpicker(String categoryTitle);

  /// English UI message used by plugins/gifs/gif_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Powered by Klipy'**
  String get poweredByKlipy;

  /// English UI message used by plugins/local_dates/local_date_composer_pill.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{label}. Activate to edit.'**
  String activateToEdit(String label);

  /// English UI message used by plugins/local_dates/local_date_composer_component.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{formatterAccountTimezoneAccountTimezone}. Activate to edit.'**
  String activateToEditLocaldatecomposercomponent(
    String formatterAccountTimezoneAccountTimezone,
  );

  /// English UI message used by plugins/local_dates/local_date_composer_component.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Local date'**
  String get localDate;

  /// English UI message used by plugins/local_dates/local_date.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'a few seconds'**
  String get aFewSeconds;

  /// English UI message used by plugins/local_dates/local_date.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'a minute'**
  String get aMinute;

  /// English UI message used by plugins/local_dates/local_date.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'an hour'**
  String get anHour;

  /// English UI message used by plugins/local_dates/local_date.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'a day'**
  String get aDay;

  /// English UI message used by plugins/local_dates/local_date.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'a month'**
  String get aMonth;

  /// English UI message used by plugins/local_dates/local_date.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'a year'**
  String get aYear;

  /// English UI message used by plugins/local_dates/local_date_widget.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Date and time'**
  String get dateAndTime;

  /// English UI message used by plugins/local_dates/local_date_widget.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dismiss date and time'**
  String get dismissDateAndTime;

  /// English UI message used by plugins/local_dates/local_date_widget.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get device;

  /// English UI message used by plugins/local_dates/local_date_widget.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get source;

  /// English UI message used by plugins/local_dates/local_dates_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'local dates disabled'**
  String get localDatesDisabled;

  /// English UI message used by plugins/local_dates/local_dates_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'local date syntax contains unsupported options'**
  String get localDateSyntaxContainsUnsupportedOptions;

  /// English UI message used by plugins/local_dates/local_dates_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'local date syntax is malformed or unsupported'**
  String get localDateSyntaxIsMalformedOrUnsupported;

  /// English UI message used by plugins/local_dates/local_dates_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'local date syntax could not be accounted for'**
  String get localDateSyntaxCouldNotBeAccountedFor;

  /// English UI message used by plugins/local_dates/local_dates_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Insert date/time'**
  String get insertDateTime;

  /// English UI message used by plugins/local_dates/local_dates_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The composer changed while this date was open. Nothing was changed.'**
  String get theComposerChangedWhileThisDateWasOpenNothingWasChanged;

  /// English UI message used by plugins/local_dates/local_dates_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The composer changed before this date could be removed. Nothing was changed.'**
  String get theComposerChangedBeforeThisDateCouldBeRemovedNothingWas;

  /// English UI message used by plugins/local_dates/local_dates_settings.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'llll z'**
  String get llllZ;

  /// English UI message used by plugins/local_dates/local_date_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose a valid start date.'**
  String get chooseAValidStartDate;

  /// English UI message used by plugins/local_dates/local_date_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose a valid start time.'**
  String get chooseAValidStartTime;

  /// English UI message used by plugins/local_dates/local_date_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose a valid end date.'**
  String get chooseAValidEndDate;

  /// English UI message used by plugins/local_dates/local_date_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'An end time needs a valid end date.'**
  String get anEndTimeNeedsAValidEndDate;

  /// English UI message used by plugins/local_dates/local_date_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose at most five preview timezones.'**
  String get chooseAtMostFivePreviewTimezones;

  /// English UI message used by plugins/local_dates/local_date_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Every timezone must be a valid IANA timezone.'**
  String get everyTimezoneMustBeAValidIANATimezone;

  /// English UI message used by plugins/local_dates/local_date_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Recurrence must look like “1.weeks”.'**
  String get recurrenceMustLookLike1Weeks;

  /// English UI message used by plugins/local_dates/local_date_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Ranges cannot recur or use countdown mode.'**
  String get rangesCannotRecurOrUseCountdownMode;

  /// English UI message used by plugins/local_dates/local_date_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The start time does not exist in that timezone.'**
  String get theStartTimeDoesNotExistInThatTimezone;

  /// English UI message used by plugins/local_dates/local_date_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The end time does not exist in that timezone.'**
  String get theEndTimeDoesNotExistInThatTimezone;

  /// English UI message used by plugins/local_dates/local_date_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The end must be after the start.'**
  String get theEndMustBeAfterTheStart;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Insert date and time'**
  String get insertDateAndTime;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit date and time'**
  String get editDateAndTime;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose the date, then check how it will appear.'**
  String get chooseTheDateThenCheckHowItWillAppear;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get when;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add end date and time'**
  String get addEndDateAndTime;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get end;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Timezone'**
  String get timezone;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Source timezone'**
  String get sourceTimezone;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This is the timezone in which the date and time were entered.'**
  String get thisIsTheTimezoneInWhichTheDateAndTimeWere;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Display options'**
  String get displayOptions;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Recurrence (optional)'**
  String get recurrenceOptional;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Countdown'**
  String get countdown;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Displayed timezone (optional)'**
  String get displayedTimezoneOptional;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Relative day'**
  String get relativeDay;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get automatic;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Always on'**
  String get alwaysOn;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Moment format (optional)'**
  String get momentFormatOptional;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'For example: LLL or YYYY-MM-DD [at] HH:mm'**
  String get forExampleLLLOrYYYYMMDDAtHHMm;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Site formats: {siteFormatsJoin}'**
  String siteFormats(String siteFormatsJoin);

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Preview timezones'**
  String get previewTimezones;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add preview timezone'**
  String get addPreviewTimezone;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add timezone'**
  String get addTimezone;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose {label} time'**
  String chooseTime(String label);

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Include {label} time'**
  String includeTime(String label);

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Complete the date to see a preview.'**
  String get completeTheDateToSeeAPreview;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Preview of the rendered date'**
  String get previewOfTheRenderedDate;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'That wall time does not exist.'**
  String get thatWallTimeDoesNotExist;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeLocaldatecomposersheet;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'None / device timezone'**
  String get noneDeviceTimezone;

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No timezones found.'**
  String get noTimezonesFound;

  /// English UI message used by plugins/voice/voice_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Call transcript draft'**
  String get callTranscriptDraft;

  /// English UI message used by plugins/voice/voice_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Voice operation {operation} failed ({errorType}).'**
  String voiceOperationFailed(String operation, String errorType);

  /// English UI message used by plugins/voice/voice_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Microphone access is blocked. Allow microphone access in your system settings, then try joining again.'**
  String get microphoneAccessIsBlockedAllowMicrophoneAccessInYourSystemSettings;

  /// English UI message used by plugins/voice/voice_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'\'t access your microphone. Check that it is connected and not in use by another app, then try again.'**
  String get weCouldnTAccessYourMicrophoneCheckThatItIsConnected;

  /// English UI message used by plugins/voice/voice_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t join {roomName}.'**
  String couldnTJoin(String roomName);

  /// English UI message used by plugins/voice/voice_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This call connects participants directly, so other participants may be able to see your IP address.'**
  String get thisCallConnectsParticipantsDirectlySoOtherParticipantsMayBeAble;

  /// English UI message used by plugins/voice/voice_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load voice rooms.'**
  String get couldnTLoadVoiceRooms;

  /// English UI message used by plugins/voice/voice_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Video was turned off in this room.'**
  String get videoWasTurnedOffInThisRoom;

  /// English UI message used by plugins/voice/voice_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You\'\'ve been moved to listeners.'**
  String get youVeBeenMovedToListeners;

  /// English UI message used by plugins/voice/voice_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You\'\'ve been made a speaker.'**
  String get youVeBeenMadeASpeaker;

  /// English UI message used by plugins/voice/voice_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This call is now being recorded.'**
  String get thisCallIsNowBeingRecorded;

  /// English UI message used by plugins/voice/voice_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The recording has stopped.'**
  String get theRecordingHasStopped;

  /// English UI message used by plugins/voice/voice_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Your request to speak was dismissed.'**
  String get yourRequestToSpeakWasDismissed;

  /// English UI message used by plugins/voice/voice_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{nameRaiserUsername} raised their hand to speak.'**
  String raisedTheirHandToSpeak(String nameRaiserUsername);

  /// English UI message used by plugins/voice/voice_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Your call session has expired. Rejoin the room to start a new one.'**
  String get yourCallSessionHasExpiredRejoinTheRoomToStartA;

  /// English UI message used by plugins/voice/voice_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You were auto-muted after being idle. Unmute to keep talking.'**
  String get youWereAutoMutedAfterBeingIdleUnmuteToKeepTalking;

  /// English UI message used by plugins/voice/voice_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You were disconnected from {callRoomName} due to inactivity.'**
  String youWereDisconnectedFromDueToInactivity(String callRoomName);

  /// English UI message used by plugins/voice/voice_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The media setting was not applied.'**
  String get theMediaSettingWasNotApplied;

  /// English UI message used by plugins/voice/voice_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t save the voice room.'**
  String get couldnTSaveTheVoiceRoom;

  /// English UI message used by plugins/voice/voice_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t delete the voice room.'**
  String get couldnTDeleteTheVoiceRoom;

  /// English UI message used by plugins/voice/voice_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load room chat.'**
  String get couldnTLoadRoomChat;

  /// English UI message used by plugins/voice/voice_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t add the member.'**
  String get couldnTAddTheMember;

  /// English UI message used by plugins/voice/voice_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t change the member\'\'s role.'**
  String get couldnTChangeTheMemberSRole;

  /// English UI message used by plugins/voice/voice_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t remove the member.'**
  String get couldnTRemoveTheMember;

  /// English UI message used by plugins/voice/voice_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The media connection could not be restored.'**
  String get theMediaConnectionCouldNotBeRestored;

  /// English UI message used by plugins/voice/voice_agents.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter an agent name.'**
  String get enterAnAgentName;

  /// English UI message used by plugins/voice/voice_agents.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Use 256 characters or fewer.'**
  String get use256CharactersOrFewer;

  /// English UI message used by plugins/voice/voice_agents.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load deployed agents. You can type a name.'**
  String get couldnTLoadDeployedAgentsYouCanTypeAName;

  /// English UI message used by plugins/voice/voice_agents.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This invitation is no longer available.'**
  String get thisInvitationIsNoLongerAvailable;

  /// English UI message used by plugins/voice/voice_agents.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t invite the agent. Try again.'**
  String get couldnTInviteTheAgentTryAgain;

  /// English UI message used by plugins/voice/voice_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'a voice room'**
  String get aVoiceRoom;

  /// English UI message used by plugins/voice/voice_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'is calling you'**
  String get isCallingYou;

  /// English UI message used by plugins/voice/voice_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'invited you to join {roomName}'**
  String invitedYouToJoin(String roomName);

  /// English UI message used by plugins/voice/voice_diagnostics.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The previous capture ended without a stop marker.'**
  String get thePreviousCaptureEndedWithoutAStopMarker;

  /// English UI message used by plugins/voice/voice_agent_invite.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invite agent'**
  String get inviteAgent;

  /// English UI message used by plugins/voice/voice_agent_invite.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invite voice agent'**
  String get inviteVoiceAgent;

  /// English UI message used by plugins/voice/voice_agent_invite.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose a deployed agent or enter its dispatch name.'**
  String get chooseADeployedAgentOrEnterItsDispatchName;

  /// English UI message used by plugins/voice/voice_agent_invite.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Agent invitation sent.'**
  String get agentInvitationSent;

  /// English UI message used by plugins/voice/voice_agent_invite.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Agent name'**
  String get agentName;

  /// English UI message used by plugins/voice/voice_agent_invite.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Deployed agent'**
  String get deployedAgent;

  /// English UI message used by plugins/voice/voice_agent_invite.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose an agent'**
  String get chooseAnAgent;

  /// English UI message used by plugins/voice/voice_agent_invite.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Type a name'**
  String get typeAName;

  /// English UI message used by plugins/voice/voice_agent_invite.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Refresh agents'**
  String get refreshAgents;

  /// English UI message used by plugins/voice/voice_agent_invite.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// English UI message used by plugins/voice/voice_agent_invite.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Send invitation'**
  String get sendInvitation;

  /// English UI message used by plugins/voice/voice_agent_invite.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Sending invitation'**
  String get sendingInvitation;

  /// English UI message used by plugins/voice/voice_report_exporter.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Recent records only. Use Share/Save for the full report.'**
  String get recentRecordsOnlyUseShareSaveForTheFullReport;

  /// English UI message used by plugins/voice/voice_report_exporter.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Save report'**
  String get saveReport;

  /// English UI message used by plugins/voice/voice_report_exporter.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Share report'**
  String get shareReport;

  /// English UI message used by plugins/voice/voice_report_exporter.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'JSON Lines diagnostics'**
  String get jSONLinesDiagnostics;

  /// English UI message used by plugins/voice/voice_report_exporter.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Voice diagnostics'**
  String get voiceDiagnostics;

  /// English UI message used by plugins/voice/voice_diagnostics_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get voice;

  /// English UI message used by plugins/voice/voice_diagnostics_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Voice capture recording'**
  String get voiceCaptureRecording;

  /// English UI message used by plugins/voice/voice_diagnostics_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Voice diagnostics are unavailable.'**
  String get voiceDiagnosticsAreUnavailable;

  /// English UI message used by plugins/voice/voice_user_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t start the call.'**
  String get couldnTStartTheCall;

  /// English UI message used by plugins/voice/voice_user_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get call;

  /// English UI message used by plugins/voice/voice_models.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Voice call'**
  String get voiceCall;

  /// English UI message used by plugins/voice/voice_models.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unsupported Voice transport'**
  String get unsupportedVoiceTransport;

  /// English UI message used by plugins/voice/voice_models.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Missing Voice room'**
  String get missingVoiceRoom;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Create voice room'**
  String get createVoiceRoom;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit voice room'**
  String get editVoiceRoom;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose how people join and participate in your room.'**
  String get chooseHowPeopleJoinAndParticipateInYourRoom;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Room details'**
  String get roomDetails;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter a room name.'**
  String get enterARoomName;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Use 80 characters or fewer.'**
  String get use80CharactersOrFewer;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'What will people talk about? (optional)'**
  String get whatWillPeopleTalkAboutOptional;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Room settings'**
  String get roomSettings;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Public room'**
  String get publicRoom;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Visible to everyone on the forum.'**
  String get visibleToEveryoneOnTheForum;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Stage room'**
  String get stageRoom;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'People join as listeners until invited to speak.'**
  String get peopleJoinAsListenersUntilInvitedToSpeak;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Allow video'**
  String get allowVideo;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Let participants share their camera and screen.'**
  String get letParticipantsShareTheirCameraAndScreen;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Maximum participants'**
  String get maximumParticipants;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Forum default'**
  String get forumDefault;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Optional, 2–200 people.'**
  String get optional2200People;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Optional, 2–50 people.'**
  String get optional250People;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Maximum media quality'**
  String get maximumMediaQuality;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Advanced settings'**
  String get advancedSettings;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Chat channel ID (optional)'**
  String get chatChannelIDOptional;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Use a channel with threading enabled for room conversations.'**
  String get useAChannelWithThreadingEnabledForRoomConversations;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'New chat thread after (minutes)'**
  String get newChatThreadAfterMinutes;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Start a fresh thread after 2–1,440 minutes of inactivity. Defaults to 15.'**
  String get startAFreshThreadAfter21440MinutesOfInactivity;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Use LiveKit'**
  String get useLiveKit;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Create room'**
  String get createRoom;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChanges;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get standard;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get high;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Maximum'**
  String get maximum;

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter a whole number of {min} or more.'**
  String enterAWholeNumberOfOrMore(String min);

  /// English UI message used by plugins/voice/voice_room_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter a whole number from {min} to {max}.'**
  String enterAWholeNumberFromTo(String min, String max);

  /// English UI message used by plugins/voice/voice_diagnostics_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'HTTP path contains /voice/'**
  String get hTTPPathContainsVoice;

  /// English UI message used by plugins/voice/voice_call_widget.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get recording;

  /// English UI message used by plugins/voice/voice_call_widget.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get unmute;

  /// English UI message used by plugins/voice/voice_call_widget.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get mute;

  /// English UI message used by plugins/voice/voice_call_widget.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Leave room'**
  String get leaveRoom;

  /// English UI message used by plugins/voice/voice_diagnostics_models.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Cand[{head}:{redactMatchGroup}:{redactMatchGroupValue3}{matchGroup}'**
  String cand(
    String head,
    String redactMatchGroup,
    String redactMatchGroupValue3,
    String matchGroup,
  );

  /// English UI message used by plugins/voice/voice_media.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'not allowed'**
  String get notAllowed;

  /// English UI message used by plugins/voice/voice_media.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'permission denied'**
  String get permissionDenied;

  /// English UI message used by plugins/voice/voice_media.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'permission dismissed'**
  String get permissionDismissed;

  /// English UI message used by plugins/voice/voice_media.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'not authorized'**
  String get notAuthorized;

  /// English UI message used by plugins/voice/voice_media.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'media access denied'**
  String get mediaAccessDenied;

  /// English UI message used by plugins/voice/voice_media.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission was denied.'**
  String get microphonePermissionWasDenied;

  /// English UI message used by plugins/voice/voice_media.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The microphone is unavailable.'**
  String get theMicrophoneIsUnavailable;

  /// English UI message used by plugins/voice/voice_media.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Voice media operation {operation} failed.'**
  String voiceMediaOperationFailed(String operation);

  /// English UI message used by plugins/voice/voice_media.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'rejected Voice track'**
  String get rejectedVoiceTrack;

  /// English UI message used by plugins/voice/voice_media.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Missing LiveKit credentials'**
  String get missingLiveKitCredentials;

  /// English UI message used by plugins/voice/voice_media.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Voice media'**
  String get voiceMedia;

  /// English UI message used by plugins/voice/voice_media.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'during LiveKit {operation}'**
  String duringLiveKit(String operation);

  /// English UI message used by plugins/voice/voice_call_controller_port.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Voice calling is unavailable.'**
  String get voiceCallingIsUnavailable;

  /// English UI message used by plugins/voice/voice_call_controller_port.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t open the voice room.'**
  String get couldnTOpenTheVoiceRoom;

  /// English UI message used by plugins/voice/voice_call_controller_port.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t update the microphone.'**
  String get couldnTUpdateTheMicrophone;

  /// English UI message used by plugins/voice/voice_call_controller_port.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t leave the voice room.'**
  String get couldnTLeaveTheVoiceRoom;

  /// English UI message used by plugins/voice/voice_preferences.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'media device'**
  String get mediaDevice;

  /// English UI message used by plugins/voice/voice_preferences.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'push-to-talk preference'**
  String get pushToTalkPreference;

  /// English UI message used by plugins/voice/voice_preferences.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'camera preference'**
  String get cameraPreference;

  /// English UI message used by plugins/voice/voice_preferences.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'privacy acknowledgement'**
  String get privacyAcknowledgement;

  /// English UI message used by plugins/voice/voice_preferences.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'status preference'**
  String get statusPreference;

  /// English UI message used by plugins/voice/voice_preferences.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'participant volume'**
  String get participantVolume;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search Voice capture'**
  String get searchVoiceCapture;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Turn on deep Voice capture?'**
  String get turnOnDeepVoiceCapture;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This records usernames and user IDs, network addresses, raw SDP and ICE negotiation, media statistics, and device details. Credentials and other secrets are redacted. Capture stays on until you turn it off or restart the app.'**
  String get thisRecordsUsernamesAndUserIDsNetworkAddressesRawSDPAnd;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Turn on capture'**
  String get turnOnCapture;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Deep capture is on'**
  String get deepCaptureIsOn;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Deep capture stopped'**
  String get deepCaptureStopped;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Clear Voice capture?'**
  String get clearVoiceCapture;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This permanently removes the retained deep-capture records from this device.'**
  String get thisPermanentlyRemovesTheRetainedDeepCaptureRecordsFromThisDevice;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Clear capture'**
  String get clearCapture;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Voice capture cleared'**
  String get voiceCaptureCleared;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Recent report copied (full report is too large)'**
  String get recentReportCopiedFullReportIsTooLarge;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Voice report copied'**
  String get voiceReportCopied;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Capture event copied'**
  String get captureEventCopied;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Voice report saved'**
  String get voiceReportSaved;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Voice report shared'**
  String get voiceReportShared;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Voice diagnostics failed: {error}'**
  String voiceDiagnosticsFailed(String error);

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Recording On'**
  String get recordingOn;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Recording Off'**
  String get recordingOff;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Deep capture stores identities, network and media negotiation, device details, and SDK logs. Secrets are redacted. Restarting the app turns recording off.'**
  String
  get deepCaptureStoresIdentitiesNetworkAndMediaNegotiationDeviceDetailsAnd;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Truncated'**
  String get truncated;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Since {diagnosticTimeTextStateStartedAtUtc}'**
  String since(String diagnosticTimeTextStateStartedAtUtc);

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Capture {stateCaptureId}'**
  String capture(String stateCaptureId);

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Copy report'**
  String get copyReport;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Turn recording off before clearing'**
  String get turnRecordingOffBeforeClearing;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Back to capture'**
  String get backToCapture;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No matching capture events'**
  String get noMatchingCaptureEvents;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Waiting for Voice activity'**
  String get waitingForVoiceActivity;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No deep-capture records'**
  String get noDeepCaptureRecords;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Change the search to see more.'**
  String get changeTheSearchToSeeMore;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Call and signaling events will appear here.'**
  String get callAndSignalingEventsWillAppearHere;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Turn recording on before reproducing the call problem.'**
  String get turnRecordingOnBeforeReproducingTheCallProblem;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'capture event'**
  String get captureEvent;

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{bytesToStringAsFixed} KiB'**
  String kiB(String bytesToStringAsFixed);

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{bytesToStringAsFixed} MiB'**
  String miB(String bytesToStringAsFixed);

  /// English UI message used by plugins/voice/voice_join.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Before you join this room'**
  String get beforeYouJoinThisRoom;

  /// English UI message used by plugins/voice/voice_join.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This room connects participants directly to each other, so while you are in the call other participants may be able to see your IP address. This is how peer-to-peer calls work and is usually harmless, but join only if you are comfortable with it.'**
  String get thisRoomConnectsParticipantsDirectlyToEachOtherSoWhileYou;

  /// English UI message used by plugins/voice/voice_join.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Don\'\'t show this again'**
  String get donTShowThisAgain;

  /// English UI message used by plugins/voice/voice_join.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Join room'**
  String get joinRoom;

  /// English UI message used by plugins/voice/voice_incoming_call.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{nameCallerUsername} is calling you'**
  String isCallingYouVoiceincomingcall(String nameCallerUsername);

  /// English UI message used by plugins/voice/voice_incoming_call.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'is calling you…'**
  String get isCallingYouVoiceincomingcallValue;

  /// English UI message used by plugins/voice/voice_incoming_call.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get answer;

  /// English UI message used by plugins/voice/voice_incoming_call.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get decline;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This voice room is unavailable.'**
  String get thisVoiceRoomIsUnavailable;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Calling {nameUserUsername}'**
  String calling(String nameUserUsername);

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Calling {nameUserUsername}…'**
  String callingVoiceroomview(String nameUserUsername);

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This call is being recorded'**
  String get thisCallIsBeingRecorded;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Recording started by @{startedBy}'**
  String recordingStartedBy(String startedBy);

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Nobody is in {roomName} yet.'**
  String nobodyIsInYet(String roomName);

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'hand raised'**
  String get handRaised;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Participant actions'**
  String get participantActions;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Local volume'**
  String get localVolume;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Notify moderators'**
  String get notifyModerators;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Make speaker'**
  String get makeSpeaker;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Move to listeners'**
  String get moveToListeners;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dismiss raised hand'**
  String get dismissRaisedHand;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove from room'**
  String get removeFromRoom;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Listen'**
  String get listen;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Deafen'**
  String get deafen;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Camera off'**
  String get cameraOff;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Camera on'**
  String get cameraOn;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Stop sharing'**
  String get stopSharing;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Share screen'**
  String get shareScreen;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Raise hand'**
  String get raiseHand;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Lower hand'**
  String get lowerHand;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invite people'**
  String get invitePeople;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Room chat'**
  String get roomChat;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Stop recording'**
  String get stopRecording;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Start recording'**
  String get startRecording;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Media settings'**
  String get mediaSettings;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit room'**
  String get editRoom;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Manage members'**
  String get manageMembers;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invite sent.'**
  String get inviteSent;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{count} invites sent.'**
  String invitesSent(String count);

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{nameNameJoin} can\'\'t be invited because they don\'\'t have access to voice rooms.'**
  String canTBeInvitedBecauseTheyDonTHaveAccessTo(String nameNameJoin);

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t send the invite.'**
  String get couldnTSendTheInvite;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invite to {roomName}'**
  String inviteTo(String roomName);

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invite by name'**
  String get inviteByName;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Send invite'**
  String get sendInvite;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'People you\'\'ve shared this room with'**
  String get peopleYouVeSharedThisRoomWith;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{timeTogetherSuggestionTotalSeconds} together recently'**
  String togetherRecently(String timeTogetherSuggestionTotalSeconds);

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invited'**
  String get invited;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get invite;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Or share an invite link'**
  String get orShareAnInviteLink;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Link copied to clipboard'**
  String get linkCopiedToClipboard;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Participant volume'**
  String get participantVolumeVoiceroomview;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get microphone;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get speaker;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get camera;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Push to talk'**
  String get pushToTalk;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Hold Space while the room is focused.'**
  String get holdSpaceWhileTheRoomIsFocused;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Show my status while in a call'**
  String get showMyStatusWhileInACall;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Sets your user status to the room you are in.'**
  String get setsYourUserStatusToTheRoomYouAreIn;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Native noise suppression'**
  String get nativeNoiseSuppression;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Echo cancellation, noise suppression, and automatic gain control are active.'**
  String get echoCancellationNoiseSuppressionAndAutomaticGainControlAreActive;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Microphone is available.'**
  String get microphoneIsAvailable;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t test the microphone. Please try again.'**
  String get couldnTTestTheMicrophonePleaseTryAgain;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Test microphone'**
  String get testMicrophone;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Testing…'**
  String get testing;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Default {label}'**
  String messageDefaultVoiceroomview(String label);

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Moderator notification is unavailable.'**
  String get moderatorNotificationIsUnavailable;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Notify moderators about @{username}'**
  String notifyModeratorsAbout(String username);

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'What should moderators know?'**
  String get whatShouldModeratorsKnow;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Notify'**
  String get notify;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Stop recording?'**
  String get stopRecordingVoiceroomview;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Start recording?'**
  String get startRecordingVoiceroomview;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The current room recording will stop.'**
  String get theCurrentRoomRecordingWillStop;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Every participant will see that this room is being recorded.'**
  String get everyParticipantWillSeeThatThisRoomIsBeingRecorded;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Message the room'**
  String get messageTheRoom;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No messages yet.'**
  String get noMessagesYetVoiceroomview;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Load older messages'**
  String get loadOlderMessages;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load the room\'\'s members.'**
  String get couldnTLoadTheRoomSMembers;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t refresh the room\'\'s members.'**
  String get couldnTRefreshTheRoomSMembers;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Members of {roomName}'**
  String membersOf(String roomName);

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'User {membershipUserId}'**
  String user(String membershipUserId);

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Change role'**
  String get changeRole;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove member'**
  String get removeMember;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// English UI message used by plugins/voice/voice_room_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add member'**
  String get addMember;

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Assign {targetName}'**
  String assign(String targetName);

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit {targetName} assignment'**
  String editAssignment(String targetName);

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dismiss {targetName} assignment'**
  String dismissAssignment(String targetName);

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Assign topic'**
  String get assignTopic;

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Assign'**
  String get assignAssignmentsheet;

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Assign to @{selectedIdentifier}'**
  String assignTo(String selectedIdentifier);

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unassign'**
  String get unassign;

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Close assignment'**
  String get closeAssignment;

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose one person or group.'**
  String get chooseOnePersonOrGroup;

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Assign to'**
  String get assignToAssignmentsheet;

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search users or groups…'**
  String get searchUsersOrGroupsAssignmentsheet;

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get group;

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Suggested'**
  String get suggested;

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search results'**
  String get searchResults;

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No matching users or groups.'**
  String get noMatchingUsersOrGroups;

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Try a different name or username.'**
  String get tryADifferentNameOrUsername;

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Selected: @{selectedIdentifier}'**
  String selected(String selectedIdentifier);

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Hide note'**
  String get hideNote;

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add a note'**
  String get addANote;

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit note'**
  String get editNote;

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get noteOptional;

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add context for the assignee…'**
  String get addContextForTheAssignee;

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Group @{assignmentAssigneeGroupName}'**
  String groupAssignmentsheet(String assignmentAssigneeGroupName);

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Status: {status}'**
  String statusAssignmentsheet(String status);

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Note: {note}'**
  String note(String note);

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{targetLabel} assigned to {assignmentAssigneeDisplayName}'**
  String assignedTo(String targetLabel, String assignmentAssigneeDisplayName);

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit assignment'**
  String get editAssignmentAssignmentsheet;

  /// English UI message used by plugins/assign/assign_user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'View all assigned'**
  String get viewAllAssigned;

  /// English UI message used by plugins/assign/assign_user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Notification preferences'**
  String get notificationPreferences;

  /// English UI message used by plugins/assign/assignment_topic_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Assigned to'**
  String get assignedToAssignmenttopiclist;

  /// English UI message used by plugins/assign/assignment_topic_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open topic to view all {allLength} assignments'**
  String openTopicToViewAllAssignments(String allLength);

  /// English UI message used by plugins/assign/assignment_topic_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'View all {allLength} assignments in topic'**
  String viewAllAssignmentsInTopic(String allLength);

  /// English UI message used by plugins/assign/assignment.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic'**
  String get topic;

  /// English UI message used by plugins/assign/assignment.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Post'**
  String get post;

  /// English UI message used by plugins/assign/assign_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to this forum to see assignment notifications.'**
  String get reconnectToThisForumToSeeAssignmentNotifications;

  /// English UI message used by plugins/assign/assign_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load assignment notifications from this forum.'**
  String get couldnTLoadAssignmentNotificationsFromThisForum;

  /// English UI message used by plugins/assign/assign_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You don’t have any assignments yet.'**
  String get youDonTHaveAnyAssignmentsYet;

  /// English UI message used by plugins/assign/assign_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Mark all unread assign notifications as read'**
  String get markAllUnreadAssignNotificationsAsRead;

  /// English UI message used by plugins/assign/assign_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'a group'**
  String get aGroup;

  /// English UI message used by plugins/assign/assign_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Are you sure? You have {unreadCount} unread assign {notifications}.'**
  String areYouSureYouHaveUnreadAssign(
    String unreadCount,
    String notifications,
  );

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Assign list'**
  String get assignList;

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Assigned'**
  String get assigned;

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Assignments'**
  String get assignments;

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Manage assignment to {directAssigneeDisplayName}'**
  String manageAssignmentTo(String directAssigneeDisplayName);

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Manage assignments'**
  String get manageAssignments;

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{postAssignmentsLength, plural, =1{{postAssignmentsLength} assigned post} other{{postAssignmentsLength} assigned posts}}'**
  String assignedPost(num postAssignmentsLength);

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Assign post'**
  String get assignPost;

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Assign this post'**
  String get assignThisPost;

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit this post assignment'**
  String get editThisPostAssignment;

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'assigned {who} to a post'**
  String assignedToAPost(String who);

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'unassigned {who} from a post'**
  String unassignedFromAPost(String who);

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'changed assignment details for {who}'**
  String changedAssignmentDetailsFor(String who);

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'changed assignment note for {who}'**
  String changedAssignmentNoteFor(String who);

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'changed assignment status for {who}'**
  String changedAssignmentStatusFor(String who);

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic unassigned. Assign topic'**
  String get topicUnassignedAssignTopic;

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open {targetLabel}'**
  String openAssignplugin(String targetLabel);

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Assigned to · {targetLabel}'**
  String assignedToAssignplugin(String targetLabel);

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Change assignee'**
  String get changeAssignee;

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Change {actionTarget} assignment'**
  String changeAssignment(String actionTarget);

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove assignment'**
  String get removeAssignment;

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove {actionTarget} assignment'**
  String removeAssignmentAssignplugin(String actionTarget);

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{targetLabel} assignment removed'**
  String assignmentRemoved(String targetLabel);

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Post #{postNumber}'**
  String postAssignplugin(String postNumber);

  /// English UI message used by plugins/assign/assigned_group_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to view group assignments.'**
  String get reconnectToViewGroupAssignments;

  /// English UI message used by plugins/assign/assigned_group_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load this group\'\'s assigned members.'**
  String get couldnTLoadThisGroupSAssignedMembers;

  /// English UI message used by plugins/assign/assigned_group_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to load more assigned members.'**
  String get reconnectToLoadMoreAssignedMembers;

  /// English UI message used by plugins/assign/assigned_group_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load more assigned members.'**
  String get couldnTLoadMoreAssignedMembers;

  /// English UI message used by plugins/assign/assigned_group_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load this group\'\'s assignments.'**
  String get couldnTLoadThisGroupSAssignments;

  /// English UI message used by plugins/assign/assigned_group_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to load more assignments.'**
  String get reconnectToLoadMoreAssignments;

  /// English UI message used by plugins/assign/assigned_group_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load more assignments.'**
  String get couldnTLoadMoreAssignments;

  /// English UI message used by plugins/assign/assign_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Assignment'**
  String get assignment;

  /// English UI message used by plugins/assign/assign_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Requires permission to view assignments.'**
  String get requiresPermissionToViewAssignments;

  /// English UI message used by plugins/assign/assign_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unassigned'**
  String get unassigned;

  /// English UI message used by plugins/assign/assign_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Username or group name'**
  String get usernameOrGroupName;

  /// English UI message used by plugins/assign/assign_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Find topics assigned to a person or group.'**
  String get findTopicsAssignedToAPersonOrGroup;

  /// English UI message used by plugins/assign/assignment_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This assignment target is no longer available.'**
  String get thisAssignmentTargetIsNoLongerAvailable;

  /// English UI message used by plugins/assign/assignment_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'An assignment update is already in progress.'**
  String get anAssignmentUpdateIsAlreadyInProgress;

  /// English UI message used by plugins/assign/assigned_group_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topics'**
  String get topics;

  /// English UI message used by plugins/assign/assigned_group_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Filter assignments'**
  String get filterAssignments;

  /// English UI message used by plugins/assign/assigned_group_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Words in the topic title'**
  String get wordsInTheTopicTitle;

  /// English UI message used by plugins/assign/assigned_group_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get everyone;

  /// English UI message used by plugins/assign/assigned_group_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Load more assignments'**
  String get loadMoreAssignments;

  /// English UI message used by plugins/assign/assigned_group_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Hide person search'**
  String get hidePersonSearch;

  /// English UI message used by plugins/assign/assigned_group_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Find assigned person'**
  String get findAssignedPerson;

  /// English UI message used by plugins/assign/assigned_group_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No active assignments match this filter.'**
  String get noActiveAssignmentsMatchThisFilter;

  /// English UI message used by plugins/discourse_ai/ai_summary_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Related'**
  String get related;

  /// English UI message used by plugins/discourse_ai/ai_summary_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Summarize'**
  String get summarize;

  /// English UI message used by plugins/discourse_ai/ai_summary_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic summary'**
  String get topicSummary;

  /// English UI message used by plugins/discourse_ai/ai_summary_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t generate this summary.'**
  String get couldnTGenerateThisSummary;

  /// English UI message used by plugins/discourse_ai/ai_summary_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This community has reached its AI credit limit for today. Please try again after {reset} or contact your site administrator for more information.'**
  String thisCommunityHasReachedItsAICreditLimitForTodayPlease(String reset);

  /// English UI message used by plugins/discourse_ai/ai_summary_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This community has reached its AI credit limit for today. Responses will be unavailable until your limit resets. Please contact your site administrator for more information.'**
  String get thisCommunityHasReachedItsAICreditLimitForTodayResponses;

  /// English UI message used by plugins/discourse_ai/ai_summary_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Regenerating summary…'**
  String get regeneratingSummary;

  /// English UI message used by plugins/discourse_ai/ai_summary_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Generating summary…'**
  String get generatingSummary;

  /// English UI message used by plugins/discourse_ai/ai_summary_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{summaryNewPostsSinceSummary, plural, =1{This summary is outdated by {summaryNewPostsSinceSummary} new post.} other{This summary is outdated by {summaryNewPostsSinceSummary} new posts.}}'**
  String thisSummaryIsOutdatedByNew(num summaryNewPostsSinceSummary);

  /// English UI message used by plugins/discourse_ai/ai_summary_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This summary is outdated.'**
  String get thisSummaryIsOutdated;

  /// English UI message used by plugins/discourse_ai/ai_summary_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Generated with {algorithm}'**
  String generatedWith(String algorithm);

  /// English UI message used by plugins/discourse_ai/ai_summary_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get regenerate;

  /// English UI message used by plugins/discourse_ai/ai_proofreading_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Proofreading isn\'\'t available right now. Nothing was posted. Try again to post without it.'**
  String get proofreadingIsnTAvailableRightNowNothingWasPostedTryAgain;

  /// English UI message used by plugins/discourse_ai/ai_proofreading_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The post changed while it was being proofread. Nothing was posted. Review it and try again.'**
  String get thePostChangedWhileItWasBeingProofreadNothingWasPosted;

  /// English UI message used by plugins/discourse_ai/ai_summary_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Summary response had no summary.'**
  String get summaryResponseHadNoSummary;

  /// English UI message used by plugins/discourse_ai/ai_proofreading_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Proofread'**
  String get proofread;

  /// English UI message used by plugins/discourse_ai/ai_proofreading_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Proofreading response contained no suggestion.'**
  String get proofreadingResponseContainedNoSuggestion;

  /// English UI message used by plugins/discourse_ai/ai_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'AiSummaryStreamFailure(type: {type})'**
  String aiSummaryStreamFailureType(String type);

  /// English UI message used by plugins/discourse_ai/ai_summary_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Summary stream timed out.'**
  String get summaryStreamTimedOut;

  /// English UI message used by plugins/discourse_github/oneboxes/commit/block.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Committed'**
  String get committed;

  /// English UI message used by plugins/discourse_github/oneboxes/issue/block.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Opened'**
  String get opened;

  /// English UI message used by plugins/discourse_events/event_calendar_skeleton.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading events'**
  String get loadingEvents;

  /// English UI message used by plugins/discourse_events/event_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'an event'**
  String get anEvent;

  /// English UI message used by plugins/discourse_events/event_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{title} is starting soon'**
  String isStartingSoon(String title);

  /// English UI message used by plugins/discourse_events/event_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{title} is happening now'**
  String isHappeningNow(String title);

  /// English UI message used by plugins/discourse_events/event_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{title} has ended'**
  String hasEnded(String title);

  /// English UI message used by plugins/discourse_events/event_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reminder for {title}'**
  String reminderFor(String title);

  /// English UI message used by plugins/discourse_events/event_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Your attendance was set for {titleRow}'**
  String yourAttendanceWasSetFor(String titleRow);

  /// English UI message used by plugins/discourse_events/event_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'set your attendance and invited you to {titleRow}'**
  String setYourAttendanceAndInvitedYouTo(String titleRow);

  /// English UI message used by plugins/discourse_events/event_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invitation to {titleRow}'**
  String invitationTo(String titleRow);

  /// English UI message used by plugins/discourse_events/event_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'invited you to {titleRow}'**
  String invitedYouToEventnotifications(String titleRow);

  /// English UI message used by plugins/discourse_events/topic_calendar_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic calendar'**
  String get topicCalendar;

  /// English UI message used by plugins/discourse_events/topic_calendar_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open web calendar'**
  String get openWebCalendar;

  /// English UI message used by plugins/discourse_events/topic_calendar_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open the original topic to view this calendar.'**
  String get openTheOriginalTopicToViewThisCalendar;

  /// English UI message used by plugins/discourse_events/event_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get events;

  /// English UI message used by plugins/discourse_events/event_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Event filter'**
  String get eventFilter;

  /// English UI message used by plugins/discourse_events/event_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'My events'**
  String get myEvents;

  /// English UI message used by plugins/discourse_events/event_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'All events'**
  String get allEvents;

  /// English UI message used by plugins/discourse_events/event_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Calendar view'**
  String get calendarView;

  /// English UI message used by plugins/discourse_events/event_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'All day'**
  String get allDay;

  /// English UI message used by plugins/discourse_events/event_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No events on this day.'**
  String get noEventsOnThisDay;

  /// English UI message used by plugins/discourse_events/event_calendar_data.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **' (local time)'**
  String get localTime;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get event;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Starts'**
  String get starts;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Ends (optional)'**
  String get endsOptional;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Repeat until (optional)'**
  String get repeatUntilOptional;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Allowed groups (comma separated)'**
  String get allowedGroupsCommaSeparated;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Meeting or event URL'**
  String get meetingOrEventURL;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get location;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Maximum attendees (optional)'**
  String get maximumAttendeesOptional;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reminders (for example: notification.15.minutes)'**
  String get remindersForExampleNotification15Minutes;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Event image URL'**
  String get eventImageURL;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Display in the event timezone'**
  String get displayInTheEventTimezone;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Minimal card'**
  String get minimalCard;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enable event chat'**
  String get enableEventChat;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enable livestream from the event URL'**
  String get enableLivestreamFromTheEventURL;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The post changed while this editor was open. Close it and reopen the event.'**
  String get thePostChangedWhileThisEditorWasOpenCloseItAnd;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter a start date and time, or select All day.'**
  String get enterAStartDateAndTimeOrSelectAllDay;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid end date.'**
  String get enterAValidEndDate;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose a valid timezone, such as Europe/Paris.'**
  String get chooseAValidTimezoneSuchAsEuropeParis;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter valid dates and times.'**
  String get enterValidDatesAndTimes;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The event must end after it starts.'**
  String get theEventMustEndAfterItStarts;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Maximum attendees must be a positive whole number.'**
  String get maximumAttendeesMustBeAPositiveWholeNumber;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose at least one allowed group for a private event.'**
  String get chooseAtLeastOneAllowedGroupForAPrivateEvent;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose date and time'**
  String get chooseDateAndTime;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add event'**
  String get addEvent;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit event'**
  String get editEvent;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Repeats'**
  String get repeats;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Does not repeat'**
  String get doesNotRepeat;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Participation'**
  String get participation;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get public;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Private groups'**
  String get privateGroups;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No attendance tracking'**
  String get noAttendanceTracking;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Description (Markdown)'**
  String get descriptionMarkdown;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptions;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove event'**
  String get removeEvent;

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'An event must be the only event in the first post of a topic.'**
  String get anEventMustBeTheOnlyEventInTheFirstPost;

  /// English UI message used by plugins/discourse_events/event_participants.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Participant details are no longer available.'**
  String get participantDetailsAreNoLongerAvailable;

  /// English UI message used by plugins/discourse_events/event_participants.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Close participants'**
  String get closeParticipants;

  /// English UI message used by plugins/discourse_events/event_participants.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Participants'**
  String get participants;

  /// English UI message used by plugins/discourse_events/event_participants.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search participants'**
  String get searchParticipants;

  /// English UI message used by plugins/discourse_events/event_participants.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{typeNull, select, true{Participants: All} other{Participants: {eventResponseLabelType}}}'**
  String participantsEventparticipants(
    String typeNull,
    String eventResponseLabelType,
  );

  /// English UI message used by plugins/discourse_events/event_participants.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Showing up to 200 people. Search to narrow the list.'**
  String get showingUpTo200PeopleSearchToNarrowTheList;

  /// English UI message used by plugins/discourse_events/event_participants.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unable to load participants'**
  String get unableToLoadParticipants;

  /// English UI message used by plugins/discourse_events/event_participants.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No participants found'**
  String get noParticipantsFound;

  /// English UI message used by plugins/discourse_events/event_participants.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Try another name or username.'**
  String get tryAnotherNameOrUsername;

  /// English UI message used by plugins/discourse_events/event_participants.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Try a different response filter.'**
  String get tryADifferentResponseFilter;

  /// English UI message used by plugins/discourse_events/event_participants.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No participants to show yet.'**
  String get noParticipantsToShowYet;

  /// English UI message used by plugins/discourse_events/event_participants.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Show all participants'**
  String get showAllParticipants;

  /// English UI message used by plugins/discourse_events/event_participants.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading participants'**
  String get loadingParticipants;

  /// English UI message used by plugins/discourse_events/event_participants.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Every occurrence'**
  String get everyOccurrence;

  /// English UI message used by plugins/discourse_events/event_participants.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You can no longer manage this event.'**
  String get youCanNoLongerManageThisEvent;

  /// English UI message used by plugins/discourse_events/event_participants.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unable to send invitations.'**
  String get unableToSendInvitations;

  /// English UI message used by plugins/discourse_events/event_participants.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Send event notifications to these usernames. For private events, access is still determined by the allowed groups.'**
  String get sendEventNotificationsToTheseUsernamesForPrivateEventsAccessIs;

  /// English UI message used by plugins/discourse_events/event_participants.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Usernames, separated by commas'**
  String get usernamesSeparatedByCommas;

  /// English UI message used by plugins/discourse_events/event_participants.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Send invitations'**
  String get sendInvitations;

  /// English UI message used by plugins/discourse_events/event_topic_title.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'View event schedule: {scheduleDescription}'**
  String viewEventSchedule(String scheduleDescription);

  /// English UI message used by plugins/discourse_events/event_topic_title.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **' · All day'**
  String get allDayEventtopictitle;

  /// English UI message used by plugins/discourse_events/event_topic_title.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Event schedule'**
  String get eventSchedule;

  /// English UI message used by plugins/discourse_events/event_topic_title.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Date unavailable'**
  String get dateUnavailable;

  /// English UI message used by plugins/discourse_events/event_topic_title.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Ends'**
  String get ends;

  /// English UI message used by plugins/discourse_events/event_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid event response'**
  String get invalidEventResponse;

  /// English UI message used by plugins/discourse_events/event_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid event list'**
  String get invalidEventList;

  /// English UI message used by plugins/discourse_events/event_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid participant list'**
  String get invalidParticipantList;

  /// English UI message used by plugins/discourse_events/discourse_events_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Upcoming events'**
  String get upcomingEvents;

  /// English UI message used by plugins/discourse_events/event_directory.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unable to load events. Try refreshing the calendar.'**
  String get unableToLoadEventsTryRefreshingTheCalendar;

  /// English UI message used by plugins/discourse_events/event_directory.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No events in this period.'**
  String get noEventsInThisPeriod;

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose recurring attendance'**
  String get chooseRecurringAttendance;

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This occurrence only'**
  String get thisOccurrenceOnly;

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'View participants'**
  String get viewParticipants;

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open event chat'**
  String get openEventChat;

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get private;

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'· Created by'**
  String get createdBy;

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Event actions'**
  String get eventActions;

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove my response'**
  String get removeMyResponse;

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Export calendar'**
  String get exportCalendar;

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open event on web'**
  String get openEventOnWeb;

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Bulk invitations and reports on web'**
  String get bulkInvitationsAndReportsOnWeb;

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open livestream'**
  String get openLivestream;

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This event is closed.'**
  String get thisEventIsClosed;

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This event has ended.'**
  String get thisEventHasEnded;

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This event is at capacity.'**
  String get thisEventIsAtCapacity;

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Connect to respond'**
  String get connectToRespond;

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading event'**
  String get loadingEvent;

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Refresh event'**
  String get refreshEvent;

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get showLess;

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Show full description'**
  String get showFullDescription;

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Going'**
  String get going;

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Interested'**
  String get interested;

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Not going'**
  String get notGoing;

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This event has no dates left to export.'**
  String get thisEventHasNoDatesLeftToExport;

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Event details are unavailable.'**
  String get eventDetailsAreUnavailable;

  /// English UI message used by plugins/discourse_events/event_time.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This event has ended'**
  String get thisEventHasEndedEventtime;

  /// English UI message used by plugins/discourse_events/event_time.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{dateFormatStart} · All day'**
  String allDayEventtime(String dateFormatStart);

  /// English UI message used by plugins/discourse_events/event_time.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{dateFormatStart} – {dateFormatEnd} · All day'**
  String allDayEventtimeValue(String dateFormatStart, String dateFormatEnd);

  /// English UI message used by plugins/discourse_events/event_time.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Every day'**
  String get everyDay;

  /// English UI message used by plugins/discourse_events/event_time.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Every weekday'**
  String get everyWeekday;

  /// English UI message used by plugins/discourse_events/event_time.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Every week'**
  String get everyWeek;

  /// English UI message used by plugins/discourse_events/event_time.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Every two weeks'**
  String get everyTwoWeeks;

  /// English UI message used by plugins/discourse_events/event_time.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Every four weeks'**
  String get everyFourWeeks;

  /// English UI message used by plugins/discourse_events/event_time.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Every month on the same weekday'**
  String get everyMonthOnTheSameWeekday;

  /// English UI message used by plugins/discourse_events/event_time.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Repeating event'**
  String get repeatingEvent;

  /// English UI message used by plugins/discourse_events/event_export.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid calendar response'**
  String get invalidCalendarResponse;

  /// English UI message used by plugins/discourse_events/group_timezones_fallback.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Group timezones, read only'**
  String get groupTimezonesReadOnly;

  /// English UI message used by plugins/discourse_events/group_timezones_fallback.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Group timezones'**
  String get groupTimezones;

  /// English UI message used by plugins/discourse_events/group_timezones_fallback.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Timezones for {group}'**
  String timezonesFor(String group);

  /// English UI message used by plugins/discourse_events/group_timezones_fallback.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Group member timezones are not available here.'**
  String get groupMemberTimezonesAreNotAvailableHere;

  /// English UI message used by plugins/discourse_events/topic_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get month;

  /// English UI message used by plugins/discourse_events/topic_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get day;

  /// English UI message used by plugins/discourse_events/topic_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Agenda'**
  String get agenda;

  /// English UI message used by plugins/discourse_events/topic_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{formatEventStart}{end} · All day'**
  String allDayTopiccalendar(String formatEventStart, String end);

  /// English UI message used by plugins/discourse_events/topic_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No calendar entries for this day.'**
  String get noCalendarEntriesForThisDay;

  /// English UI message used by plugins/discourse_events/topic_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'View reply #{number}'**
  String viewReply(String number);

  /// English UI message used by plugins/discourse_events/topic_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'All weekdays are hidden in this calendar.'**
  String get allWeekdaysAreHiddenInThisCalendar;

  /// English UI message used by plugins/discourse_events/topic_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Calendars with hidden weekdays are not supported.'**
  String get calendarsWithHiddenWeekdaysAreNotSupported;

  /// English UI message used by plugins/discourse_events/topic_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{viewCalendarViewAgenda, select, true{Previous month} other{Previous {viewLabel}}}'**
  String previousTopiccalendar(String viewCalendarViewAgenda, String viewLabel);

  /// English UI message used by plugins/discourse_events/topic_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{viewCalendarViewAgenda, select, true{Next month} other{Next {viewLabel}}}'**
  String nextTopiccalendar(String viewCalendarViewAgenda, String viewLabel);

  /// English UI message used by plugins/discourse_events/topic_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No calendar entries this month.'**
  String get noCalendarEntriesThisMonth;

  /// English UI message used by plugins/discourse_events/topic_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No calendar entries in this view.'**
  String get noCalendarEntriesInThisView;

  /// English UI message used by plugins/discourse_events/topic_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{numberOfHiddenRows} more entries'**
  String moreEntries(String numberOfHiddenRows);

  /// English UI message used by plugins/discourse_events/topic_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Calendar timezone'**
  String get calendarTimezone;

  /// English UI message used by plugins/discourse_events/topic_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search timezones'**
  String get searchTimezones;

  /// English UI message used by plugins/discourse_events/event_data.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'going|interested|not going'**
  String get goingInterestedNotGoing;

  /// English UI message used by plugins/discourse_events/event_data.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get schedule;

  /// English UI message used by plugins/discourse_events/event_data.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get year;

  /// English UI message used by plugins/discourse_events/event_composer_parser.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Attribute values cannot contain line breaks or both kinds of quotation mark.'**
  String get attributeValuesCannotContainLineBreaksOrBothKindsOfQuotation;

  /// English UI message used by plugins/discourse_events/topic_calendar_data.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Calendar entry'**
  String get calendarEntry;

  /// English UI message used by plugins/discourse_events/event_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unable to load this event. Try again.'**
  String get unableToLoadThisEventTryAgain;

  /// English UI message used by plugins/discourse_events/event_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unable to confirm the change. The event has been refreshed; check your response before trying again.'**
  String get unableToConfirmTheChangeTheEventHasBeenRefreshedCheck;

  /// English UI message used by plugins/solved/solved_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Solution'**
  String get solution;

  /// English UI message used by plugins/solved/solved_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Find solved topics or unsolved topics in categories that support solutions.'**
  String get findSolvedTopicsOrUnsolvedTopicsInCategoriesThatSupportSolutions;

  /// English UI message used by plugins/solved/solved_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Solved'**
  String get solved;

  /// English UI message used by plugins/solved/solved_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unsolved'**
  String get unsolved;

  /// English UI message used by plugins/poll/poll_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Always visible'**
  String get alwaysVisible;

  /// English UI message used by plugins/poll/poll_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'After voting'**
  String get afterVoting;

  /// English UI message used by plugins/poll/poll_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'After the poll closes'**
  String get afterThePollCloses;

  /// English UI message used by plugins/poll/poll_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Staff only'**
  String get staffOnly;

  /// English UI message used by plugins/poll/poll_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// English UI message used by plugins/poll/poll_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The site poll option limit is unavailable.'**
  String get theSitePollOptionLimitIsUnavailable;

  /// English UI message used by plugins/poll/poll_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Ranked-choice polls can only be created on the web.'**
  String get rankedChoicePollsCanOnlyBeCreatedOnTheWeb;

  /// English UI message used by plugins/poll/poll_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The type of an existing ranked-choice poll cannot change.'**
  String get theTypeOfAnExistingRankedChoicePollCannotChange;

  /// English UI message used by plugins/poll/poll_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This poll type can only be edited as raw source.'**
  String get thisPollTypeCanOnlyBeEditedAsRawSource;

  /// English UI message used by plugins/poll/poll_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Only staff can make poll results staff-only.'**
  String get onlyStaffCanMakePollResultsStaffOnly;

  /// English UI message used by plugins/poll/poll_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Automatic close must be a valid ISO-8601 date and time.'**
  String get automaticCloseMustBeAValidISO8601DateAndTime;

  /// English UI message used by plugins/poll/poll_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Minimum must be zero or greater.'**
  String get minimumMustBeZeroOrGreater;

  /// English UI message used by plugins/poll/poll_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Maximum must be greater than or equal to minimum.'**
  String get maximumMustBeGreaterThanOrEqualToMinimum;

  /// English UI message used by plugins/poll/poll_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Step must be at least 1.'**
  String get stepMustBeAtLeast1;

  /// English UI message used by plugins/poll/poll_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'A number poll must generate at least two options.'**
  String get aNumberPollMustGenerateAtLeastTwoOptions;

  /// English UI message used by plugins/poll/poll_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'A poll can have at most {maximumOptions} generated options.'**
  String aPollCanHaveAtMostGeneratedOptions(String maximumOptions);

  /// English UI message used by plugins/poll/poll_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Every option needs text.'**
  String get everyOptionNeedsText;

  /// English UI message used by plugins/poll/poll_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'A poll needs at least two options.'**
  String get aPollNeedsAtLeastTwoOptions;

  /// English UI message used by plugins/poll/poll_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'A poll can have at most {maximumOptions} options.'**
  String aPollCanHaveAtMostOptions(String maximumOptions);

  /// English UI message used by plugins/poll/poll_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Poll options must be unique.'**
  String get pollOptionsMustBeUnique;

  /// English UI message used by plugins/poll/poll_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Multiple choice requires 1 ≤ minimum ≤ maximum ≤ option count, with minimum below the option count.'**
  String get multipleChoiceRequires1MinimumMaximumOptionCountWithMinimumBelow;

  /// English UI message used by plugins/poll/poll_composer_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The composer changed while this poll was open. Nothing was changed.'**
  String get theComposerChangedWhileThisPollWasOpenNothingWasChanged;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add poll'**
  String get addPoll;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit poll'**
  String get editPoll;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This poll may already have votes.'**
  String get thisPollMayAlreadyHaveVotes;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{voterCount, plural, =1{This poll has {voterCount} voter.} other{This poll has {voterCount} voters.}}'**
  String thisPollHas(num voterCount);

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove published poll?'**
  String get removePublishedPoll;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{detail} Removing it will remove the poll from the post.'**
  String removingItWillRemoveThePollFromThePost(String detail);

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove poll'**
  String get removePoll;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Title (optional)'**
  String get titleOptional;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Lunch choice'**
  String get lunchChoice;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Ranked-choice polls keep their type. Voting remains available on the web.'**
  String get rankedChoicePollsKeepTheirTypeVotingRemainsAvailableOnThe;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Public voter identities'**
  String get publicVoterIdentities;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The voter list itself is shown on the web in this version.'**
  String get theVoterListItselfIsShownOnTheWebInThis;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Automatic close'**
  String get automaticClose;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Close date and time'**
  String get closeDateAndTime;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'ISO 8601, in this device\'\'s time zone unless one is given'**
  String get iSO8601InThisDeviceSTimeZoneUnlessOneIs;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Poll type'**
  String get pollType;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Single choice'**
  String get singleChoice;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Multiple choice'**
  String get multipleChoice;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get number;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Ranked choice'**
  String get rankedChoice;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Option {index}'**
  String optionPollcomposersheet(String index);

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Move option up'**
  String get moveOptionUp;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Move option down'**
  String get moveOptionDown;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove option'**
  String get removeOption;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add option'**
  String get addOption;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Minimum choices'**
  String get minimumChoices;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Maximum choices'**
  String get maximumChoices;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Number range'**
  String get numberRange;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Minimum'**
  String get minimum;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Step'**
  String get step;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Options are generated inclusively from this range.'**
  String get optionsAreGeneratedInclusivelyFromThisRange;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Show results'**
  String get showResults;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Preserve “{draftResultsSource}”'**
  String preserve(String draftResultsSource);

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Automatic close needs a date and time.'**
  String get automaticCloseNeedsADateAndTime;

  /// English UI message used by plugins/poll/poll_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Minimum, maximum, and step must be whole numbers.'**
  String get minimumMaximumAndStepMustBeWholeNumbers;

  /// English UI message used by plugins/poll/poll_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Poll'**
  String get poll;

  /// English UI message used by plugins/poll/poll_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The composer changed before this poll could be removed. Nothing was changed.'**
  String get theComposerChangedBeforeThisPollCouldBeRemovedNothingWas;

  /// English UI message used by plugins/poll/poll_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t save that vote.'**
  String get couldnTSaveThatVote;

  /// English UI message used by plugins/poll/poll_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Polls'**
  String get polls;

  /// English UI message used by plugins/poll/poll_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Find posts containing polls.'**
  String get findPostsContainingPolls;

  /// English UI message used by plugins/poll/poll_global_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Contains a poll'**
  String get containsAPoll;

  /// English UI message used by plugins/poll/poll_composer_pill.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{nullTitleIsEmpty, select, true{Poll · Untitled · {optionCount} {noun}} other{Poll · {title} · {optionCount} {noun}}}'**
  String pollPollcomposerpill(
    String nullTitleIsEmpty,
    String optionCount,
    String noun,
    String title,
  );

  /// English UI message used by plugins/poll/poll_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Voting is unavailable in archived topics.'**
  String get votingIsUnavailableInArchivedTopics;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This poll is closed.'**
  String get thisPollIsClosed;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This poll has an unsupported status and is read only.'**
  String get thisPollHasAnUnsupportedStatusAndIsReadOnly;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Voting is unavailable because this topic is archived.'**
  String get votingIsUnavailableBecauseThisTopicIsArchived;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Connect an account to vote.'**
  String get connectAnAccountToVote;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Your group membership could not be confirmed, so this poll is read only.'**
  String get yourGroupMembershipCouldNotBeConfirmedSoThisPollIs;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Only members of {humanListPollGroups} can vote in this poll.'**
  String onlyMembersOfCanVoteInThisPoll(String humanListPollGroups);

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Weighted average: {formatAverageCalculateNumberPollAverageP}'**
  String weightedAverage(String formatAverageCalculateNumberPollAverageP);

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose exactly {multipleMin}.'**
  String chooseExactly(String multipleMin);

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose between {multipleMin} and {multipleMax} options.'**
  String chooseBetweenAndOptions(String multipleMin, String multipleMax);

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove votes'**
  String get removeVotes;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Cast votes'**
  String get castVotes;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Ranked-choice voting is available on the web.'**
  String get rankedChoiceVotingIsAvailableOnTheWeb;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This poll type is read only in the app. You can vote on the web.'**
  String get thisPollTypeIsReadOnlyInTheAppYouCan;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This poll has no options that can be displayed.'**
  String get thisPollHasNoOptionsThatCanBeDisplayed;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Saving vote…'**
  String get savingVote;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Vote on web'**
  String get voteOnWeb;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Connect account'**
  String get connectAccount;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Results will be shown when this poll closes.'**
  String get resultsWillBeShownWhenThisPollCloses;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Results are not available.'**
  String get resultsAreNotAvailable;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Vote to see results.'**
  String get voteToSeeResults;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Results are visible to staff.'**
  String get resultsAreVisibleToStaff;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'1 voter'**
  String get message1Voter;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Private voter identities'**
  String get privateVoterIdentities;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dynamic options'**
  String get dynamicOptions;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Restricted to {humanListPollGroups}'**
  String restrictedTo(String humanListPollGroups);

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Automatically closed'**
  String get automaticallyClosed;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'1 vote'**
  String get message1Vote;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Tie between'**
  String get tieBetween;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Winner'**
  String get winner;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Ranked-choice results are not available yet.'**
  String get rankedChoiceResultsAreNotAvailableYet;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Automatically closed {date} at {time}.'**
  String automaticallyClosedAt(String date, String time);

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Closes {date} at {time}.'**
  String closesAt(String date, String time);

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Poll, read only'**
  String get pollReadOnly;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This poll cannot be displayed interactively.'**
  String get thisPollCannotBeDisplayedInteractively;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get unavailable;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **' Spoiler '**
  String get spoiler;

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// English UI message used by shell/draft_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove draft?'**
  String get removeDraft;

  /// English UI message used by shell/draft_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'“{draftDisplayTitle}” will be permanently removed from this account.'**
  String willBePermanentlyRemovedFromThisAccount(String draftDisplayTitle);

  /// English UI message used by shell/draft_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Connect this account to see its drafts'**
  String get connectThisAccountToSeeItsDrafts;

  /// English UI message used by shell/draft_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No drafts yet'**
  String get noDraftsYet;

  /// English UI message used by shell/draft_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Replies and topics you start writing will appear here.'**
  String get repliesAndTopicsYouStartWritingWillAppearHere;

  /// English UI message used by shell/draft_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading drafts'**
  String get loadingDrafts;

  /// English UI message used by shell/draft_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove draft'**
  String get removeDraftDraftlist;

  /// English UI message used by shell/app_settings_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Close settings'**
  String get closeSettings;

  /// English UI message used by shell/app_settings_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Preferences for all your forums.'**
  String get preferencesForAllYourForums;

  /// English UI message used by shell/app_settings_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Limit content size'**
  String get limitContentSize;

  /// English UI message used by shell/app_settings_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Center content in each panel with a maximum width of 825 px.'**
  String get centerContentInEachPanelWithAMaximumWidthOf825;

  /// English UI message used by shell/app_settings_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Disable GIF animations'**
  String get disableGIFAnimations;

  /// English UI message used by shell/app_settings_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Pause GIFs by default in posts and chat messages.'**
  String get pauseGIFsByDefaultInPostsAndChatMessages;

  /// English UI message used by shell/app_settings_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not save the font.'**
  String get couldNotSaveTheFont;

  /// English UI message used by shell/app_settings_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get font;

  /// English UI message used by shell/app_settings_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Used for reading and writing in every forum.'**
  String get usedForReadingAndWritingInEveryForum;

  /// English UI message used by shell/app_settings_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The quick brown fox jumps over the lazy dog.'**
  String get theQuickBrownFoxJumpsOverTheLazyDog;

  /// English UI message used by shell/app_settings_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not save the effects.'**
  String get couldNotSaveTheEffects;

  /// English UI message used by shell/app_settings_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Effects'**
  String get effects;

  /// English UI message used by shell/app_settings_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Drawn over the colours of every forum.'**
  String get drawnOverTheColoursOfEveryForum;

  /// English UI message used by shell/app_settings_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get textSize;

  /// English UI message used by shell/app_settings_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Text size controls'**
  String get textSizeControls;

  /// English UI message used by shell/app_settings_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Decrease text size'**
  String get decreaseTextSize;

  /// English UI message used by shell/app_settings_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Current text size'**
  String get currentTextSize;

  /// English UI message used by shell/app_settings_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Increase text size'**
  String get increaseTextSize;

  /// English UI message used by shell/app_settings_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts:'**
  String get shortcuts;

  /// English UI message used by shell/app_settings_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'to resize ·'**
  String get toResize;

  /// English UI message used by shell/app_settings_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'to reset'**
  String get toReset;

  /// English UI message used by shell/keyboard_shortcuts_help.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get keyboardShortcuts;

  /// English UI message used by shell/keyboard_shortcuts_help.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Shift+J and Shift+K select topics without opening them. J and K move through posts in the open topic. When no topic is open, J and K select topics in the list. G then J or K opens the next or previous topic. Navigation shortcuts pause while you type or use a menu.'**
  String get shiftJAndShiftKSelectTopicsWithoutOpeningThemJ;

  /// English UI message used by shell/keyboard_shortcuts_help.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Back in current tab'**
  String get backInCurrentTab;

  /// English UI message used by shell/keyboard_shortcuts_help.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Forward in current tab'**
  String get forwardInCurrentTab;

  /// English UI message used by shell/keyboard_shortcuts_help.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Refresh current tab'**
  String get refreshCurrentTab;

  /// English UI message used by shell/keyboard_shortcuts_help.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'New topic'**
  String get newTopic;

  /// English UI message used by shell/keyboard_shortcuts_help.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reply to topic'**
  String get replyToTopic;

  /// English UI message used by shell/keyboard_shortcuts_help.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Bookmark topic'**
  String get bookmarkTopic;

  /// English UI message used by shell/keyboard_shortcuts_help.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Submit composer'**
  String get submitComposer;

  /// English UI message used by shell/keyboard_shortcuts_help.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Close composer'**
  String get closeComposer;

  /// English UI message used by shell/keyboard_shortcuts_help.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Global search'**
  String get globalSearch;

  /// English UI message used by shell/keyboard_shortcuts_help.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Contextual search'**
  String get contextualSearch;

  /// English UI message used by shell/composer_details_blocks.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Use a single line for the summary.'**
  String get useASingleLineForTheSummary;

  /// English UI message used by shell/composer_details_blocks.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The summary contains too many quotation styles.'**
  String get theSummaryContainsTooManyQuotationStyles;

  /// English UI message used by shell/inline_video_playback.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The platform video player failed.'**
  String get thePlatformVideoPlayerFailed;

  /// English UI message used by shell/topic_move_posts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t open the destination topic.'**
  String get couldnTOpenTheDestinationTopic;

  /// English UI message used by shell/topic_move_posts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Move posts'**
  String get movePosts;

  /// English UI message used by shell/topic_move_posts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Move {count} selected post.} other{Move {count} selected posts.}}'**
  String moveSelected(num count);

  /// English UI message used by shell/topic_move_posts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Existing message'**
  String get existingMessage;

  /// English UI message used by shell/topic_move_posts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Existing topic'**
  String get existingTopic;

  /// English UI message used by shell/topic_move_posts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Create and move'**
  String get createAndMove;

  /// English UI message used by shell/topic_move_posts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Message title'**
  String get messageTitle;

  /// English UI message used by shell/topic_move_posts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic title'**
  String get topicTitle;

  /// English UI message used by shell/topic_move_posts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Default category'**
  String get defaultCategory;

  /// English UI message used by shell/topic_move_posts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search by message title or ID'**
  String get searchByMessageTitleOrID;

  /// English UI message used by shell/topic_move_posts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search by topic title or ID'**
  String get searchByTopicTitleOrID;

  /// English UI message used by shell/topic_move_posts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search for a destination topic.'**
  String get searchForADestinationTopic;

  /// English UI message used by shell/topic_move_posts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search for a destination message.'**
  String get searchForADestinationMessage;

  /// English UI message used by shell/topic_move_posts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No topics found.'**
  String get noTopicsFound;

  /// English UI message used by shell/topic_move_posts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No messages found.'**
  String get noMessagesFound;

  /// English UI message used by shell/topic_move_posts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get messageTopicmoveposts;

  /// English UI message used by shell/topic_move_posts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Preserve chronological order'**
  String get preserveChronologicalOrder;

  /// English UI message used by shell/composer_todos.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'To-do'**
  String get toDo;

  /// English UI message used by shell/composer_block_surface.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get moveUp;

  /// English UI message used by shell/composer_block_surface.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get moveDown;

  /// English UI message used by shell/composer_block_surface.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Drag to move or click to open menu'**
  String get dragToMoveOrClickToOpenMenu;

  /// English UI message used by shell/composer_block_surface.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add block'**
  String get addBlock;

  /// English UI message used by shell/composer_block_surface.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Empty paragraph actions'**
  String get emptyParagraphActions;

  /// English UI message used by shell/composer_list_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get list;

  /// English UI message used by shell/composer_list_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'List item content'**
  String get listItemContent;

  /// English UI message used by shell/composer_block_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Quote'**
  String get quote;

  /// English UI message used by shell/composer_block_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get gallery;

  /// English UI message used by shell/composer_block_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get image;

  /// English UI message used by shell/composer_block_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The draft changed. Move the block again.'**
  String get theDraftChangedMoveTheBlockAgain;

  /// English UI message used by shell/desktop_navigation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Community navigation'**
  String get communityNavigation;

  /// English UI message used by shell/desktop_navigation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Navigation'**
  String get navigation;

  /// English UI message used by shell/topic_inbox_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading topic details'**
  String get loadingTopicDetails;

  /// English UI message used by shell/topic_inbox_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading topic activity'**
  String get loadingTopicActivity;

  /// English UI message used by shell/topic_inbox_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading topic title'**
  String get loadingTopicTitle;

  /// English UI message used by shell/topic_inbox_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic closed'**
  String get topicClosed;

  /// English UI message used by shell/topic_inbox_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Latest topics'**
  String get latestTopics;

  /// English UI message used by shell/topic_inbox_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Back to {content} list'**
  String backToList(String content);

  /// English UI message used by shell/topic_inbox_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Collapse {content}'**
  String collapseTopicinboxheader(String content);

  /// English UI message used by shell/topic_inbox_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'min read'**
  String get minRead;

  /// English UI message used by shell/topic_inbox_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'last activity just now'**
  String get lastActivityJustNow;

  /// English UI message used by shell/topic_inbox_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'last activity {age} ago'**
  String lastActivityAgo(String age);

  /// English UI message used by shell/topic_inbox_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic reminders'**
  String get topicReminders;

  /// English UI message used by shell/topic_inbox_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove subcategory'**
  String get removeSubcategory;

  /// English UI message used by shell/topic_inbox_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Move to Uncategorized'**
  String get moveToUncategorized;

  /// English UI message used by shell/topic_inbox_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'+ Subcategory'**
  String get subcategory;

  /// English UI message used by shell/topic_inbox_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'+ Category'**
  String get categoryTopicinboxheader;

  /// English UI message used by shell/topic_inbox_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Browse {valueName}'**
  String browseTopicinboxheader(String valueName);

  /// English UI message used by shell/topic_inbox_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit topic subcategory'**
  String get editTopicSubcategory;

  /// English UI message used by shell/topic_inbox_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit topic category'**
  String get editTopicCategory;

  /// English UI message used by shell/topic_inbox_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Saving category'**
  String get savingCategory;

  /// English UI message used by shell/topic_inbox_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Browse {categoryName}'**
  String browseTopicinboxheaderValue(String categoryName);

  /// English UI message used by shell/topic_inbox_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dismiss {sectionLabel}'**
  String dismissTopicinboxheader(String sectionLabel);

  /// English UI message used by shell/topic_inbox_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// English UI message used by shell/content_navigation_controls.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Back (mouse back button)'**
  String get backMouseBackButton;

  /// English UI message used by shell/content_navigation_controls.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Forward (mouse forward button)'**
  String get forwardMouseForwardButton;

  /// English UI message used by shell/content_navigation_controls.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get forward;

  /// English UI message used by shell/badges_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{routeIsDirectory, select, true{Couldn\'\'t load badges.} other{Couldn\'\'t load this badge.}}'**
  String couldnTLoad(String routeIsDirectory);

  /// English UI message used by shell/badges_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load badge recipients.'**
  String get couldnTLoadBadgeRecipients;

  /// English UI message used by shell/topic_tag_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dismiss tags picker'**
  String get dismissTagsPicker;

  /// English UI message used by shell/topic_tag_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tags;

  /// English UI message used by shell/topic_tag_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load tags.'**
  String get couldnTLoadTags;

  /// English UI message used by shell/topic_tag_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Find or add tags…'**
  String get findOrAddTags;

  /// English UI message used by shell/topic_tag_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Create new tag: “{newTagName}”'**
  String createNewTag(String newTagName);

  /// English UI message used by shell/topic_tag_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open tag {tagName}'**
  String openTag(String tagName);

  /// English UI message used by shell/topic_tag_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No tags available.'**
  String get noTagsAvailable;

  /// English UI message used by shell/topic_tag_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No matching tags.'**
  String get noMatchingTags;

  /// English UI message used by shell/directory_skeleton.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading {kindName}'**
  String loadingDirectoryskeleton(String kindName);

  /// English UI message used by shell/account_activity_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to {instanceHost} to see notifications.'**
  String reconnectToToSeeNotifications(String instanceHost);

  /// English UI message used by shell/account_activity_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load notifications from {instanceHost}.'**
  String couldnTLoadNotificationsFrom(String instanceHost);

  /// English UI message used by shell/account_activity_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to {instanceHost} to see replies.'**
  String reconnectToToSeeReplies(String instanceHost);

  /// English UI message used by shell/account_activity_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load replies from {instanceHost}.'**
  String couldnTLoadRepliesFrom(String instanceHost);

  /// English UI message used by shell/account_activity_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to {instanceHost} to see likes.'**
  String reconnectToToSeeLikes(String instanceHost);

  /// English UI message used by shell/account_activity_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load likes from {instanceHost}.'**
  String couldnTLoadLikesFrom(String instanceHost);

  /// English UI message used by shell/account_activity_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to {instanceHost} to see other notifications.'**
  String reconnectToToSeeOtherNotifications(String instanceHost);

  /// English UI message used by shell/account_activity_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load other notifications from {instanceHost}.'**
  String couldnTLoadOtherNotificationsFrom(String instanceHost);

  /// English UI message used by shell/account_activity_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Not allowed — try reconnecting to {instanceHost}.'**
  String notAllowedTryReconnectingTo(String instanceHost);

  /// English UI message used by shell/account_activity_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t reach {instanceHost}.'**
  String couldnTReach(String instanceHost);

  /// English UI message used by shell/account_activity_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to {instanceHost} to see your bookmarks.'**
  String reconnectToToSeeYourBookmarks(String instanceHost);

  /// English UI message used by shell/account_activity_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load bookmarks from {instanceHost}.'**
  String couldnTLoadBookmarksFrom(String instanceHost);

  /// English UI message used by shell/account_activity_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to {instanceHost} to see your activity.'**
  String reconnectToToSeeYourActivity(String instanceHost);

  /// English UI message used by shell/account_activity_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load activity from {instanceHost}.'**
  String couldnTLoadActivityFrom(String instanceHost);

  /// English UI message used by shell/topic_feed_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load {instanceHost}.'**
  String couldnTLoadTopicfeedcontroller(String instanceHost);

  /// English UI message used by shell/topic_feed_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load more topics from {instanceHost}.'**
  String couldnTLoadMoreTopicsFrom(String instanceHost);

  /// English UI message used by shell/group_pages_host.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unknown group route.'**
  String get unknownGroupRoute;

  /// English UI message used by shell/group_pages_host.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Leave {groupLabel}?'**
  String leaveGrouppageshost(String groupLabel);

  /// English UI message used by shell/group_pages_host.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You won\'\'t be able to join it again on your own.'**
  String get youWonTBeAbleToJoinItAgainOnYour;

  /// English UI message used by shell/group_pages_host.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Leave group'**
  String get leaveGroup;

  /// English UI message used by shell/group_pages_host.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Update existing members?'**
  String get updateExistingMembers;

  /// English UI message used by shell/group_pages_host.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This change also affects the notification preferences of {userCount} existing {members}. Apply it to them too?'**
  String thisChangeAlsoAffectsTheNotificationPreferencesOfExistingApplyIt(
    String userCount,
    String members,
  );

  /// English UI message used by shell/group_pages_host.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Only new members'**
  String get onlyNewMembers;

  /// English UI message used by shell/group_pages_host.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Update {userCount} {members}'**
  String update(String userCount, String members);

  /// English UI message used by shell/group_pages_host.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Request to join {groupLabel}'**
  String requestToJoin(String groupLabel);

  /// English UI message used by shell/group_pages_host.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get reason;

  /// English UI message used by shell/group_pages_host.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Send request'**
  String get sendRequest;

  /// English UI message used by shell/topic_filter_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// English UI message used by shell/topic_filter_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Last week'**
  String get lastWeek;

  /// English UI message used by shell/topic_filter_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Last month'**
  String get lastMonth;

  /// English UI message used by shell/topic_filter_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Last year'**
  String get lastYear;

  /// English UI message used by shell/notification_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Mark notifications as read?'**
  String get markNotificationsAsRead;

  /// English UI message used by shell/notification_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t mark notifications as read. Try again.'**
  String get couldnTMarkNotificationsAsReadTryAgain;

  /// English UI message used by shell/notification_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading notifications'**
  String get loadingNotifications;

  /// English UI message used by shell/notification_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You haven\'\'t received any likes yet.'**
  String get youHavenTReceivedAnyLikesYet;

  /// English UI message used by shell/notification_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You don’t have any other notifications yet.'**
  String get youDonTHaveAnyOtherNotificationsYet;

  /// English UI message used by shell/notification_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Nothing new.'**
  String get nothingNew;

  /// English UI message used by shell/topic_list_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No topics found. Try another search or change the filters.'**
  String get noTopicsFoundTryAnotherSearchOrChangeTheFilters;

  /// English UI message used by shell/topic_list_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You\'\'re all caught up.'**
  String get youReAllCaughtUp;

  /// English UI message used by shell/topic_list_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet.'**
  String get nothingHereYet;

  /// English UI message used by shell/topic_list_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading messages'**
  String get loadingMessages;

  /// English UI message used by shell/topic_list_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading filtered topics'**
  String get loadingFilteredTopics;

  /// English UI message used by shell/topic_list_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading topics'**
  String get loadingTopics;

  /// English UI message used by shell/topic_list_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'new topic'**
  String get newTopicTopiclistview;

  /// English UI message used by shell/topic_list_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'new or updated topic'**
  String get newOrUpdatedTopic;

  /// English UI message used by shell/topic_list_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{See {count} {noun}} other{See {count} {noun}s}}'**
  String see(num count, String noun);

  /// English UI message used by shell/topic_list_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Category path'**
  String get categoryPath;

  /// English UI message used by shell/topic_list_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Parent category: {parentName}'**
  String parentCategory(String parentName);

  /// English UI message used by shell/topic_list_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Category: {categoryName}'**
  String categoryTopiclistview(String categoryName);

  /// English UI message used by shell/topic_list_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Tag: {tagName}'**
  String tag(String tagName);

  /// English UI message used by shell/badges_host.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Badges are disabled on this forum.'**
  String get badgesAreDisabledOnThisForum;

  /// English UI message used by shell/group_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This group feature is unavailable.'**
  String get thisGroupFeatureIsUnavailable;

  /// English UI message used by shell/group_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unknown group section.'**
  String get unknownGroupSection;

  /// English UI message used by shell/group_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The group could not be deleted.'**
  String get theGroupCouldNotBeDeleted;

  /// English UI message used by shell/group_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Join group'**
  String get joinGroup;

  /// English UI message used by shell/group_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Request to join'**
  String get requestToJoinGrouppage;

  /// English UI message used by shell/group_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Group actions'**
  String get groupActions;

  /// English UI message used by shell/group_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Delete group'**
  String get deleteGroup;

  /// English UI message used by shell/group_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'More group actions'**
  String get moreGroupActions;

  /// English UI message used by shell/group_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get owner;

  /// English UI message used by shell/group_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get member;

  /// English UI message used by shell/group_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Delete group?'**
  String get deleteGroupGrouppage;

  /// English UI message used by shell/group_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone. Type “{groupName}” to confirm.'**
  String thisCannotBeUndoneTypeToConfirm(String groupName);

  /// English UI message used by shell/group_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupName;

  /// English UI message used by shell/group_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get deletePermanently;

  /// English UI message used by shell/group_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activity;

  /// English UI message used by shell/group_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get requests;

  /// English UI message used by shell/group_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get manage;

  /// English UI message used by shell/group_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get permissions;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Notification counter {idId} is not registered.'**
  String notificationCounterIsNotRegistered(String idId);

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Plugin {consumer} cannot update notification counter {idId}.'**
  String pluginCannotUpdateNotificationCounter(String consumer, String idId);

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Plugin {consumer} cannot build composer target {requestKindId}.'**
  String pluginCannotBuildComposerTarget(String consumer, String requestKindId);

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Timed out {description}.'**
  String timedOut(String description);

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to dismiss new topics.'**
  String get reconnectToDismissNewTopics;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not dismiss new topics. Please try again.'**
  String get couldNotDismissNewTopicsPleaseTryAgain;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load the presence setting. Try again.'**
  String get couldnTLoadThePresenceSettingTryAgain;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{host} no longer accepts this sign-in. Sign in again to continue.'**
  String noLongerAcceptsThisSignInSignInAgainToContinue(String host);

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The sign-in for {host} is no longer saved on this device. Sign in again to continue.'**
  String theSignInForIsNoLongerSavedOnThisDevice(String host);

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reconnect this account to load its presence setting.'**
  String get reconnectThisAccountToLoadItsPresenceSetting;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t update presence. Check the connection and try again.'**
  String get couldnTUpdatePresenceCheckTheConnectionAndTryAgain;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The site didn\'\'t accept that presence setting.'**
  String get theSiteDidnTAcceptThatPresenceSetting;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Too fast — try changing presence again in {waitInSeconds}s.'**
  String tooFastTryChangingPresenceAgainInS(String waitInSeconds);

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Too fast — try changing presence again in a moment.'**
  String get tooFastTryChangingPresenceAgainInAMoment;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Presence could not be changed. Reconnect this account and try again.'**
  String get presenceCouldNotBeChangedReconnectThisAccountAndTryAgain;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Presence changed somewhere else. Try again to use this setting.'**
  String get presenceChangedSomewhereElseTryAgainToUseThisSetting;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Custom status is not available for this account.'**
  String get customStatusIsNotAvailableForThisAccount;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Another status change is still finishing.'**
  String get anotherStatusChangeIsStillFinishing;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose a time in the future.'**
  String get chooseATimeInTheFuture;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get users;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This topic can no longer be changed.'**
  String get thisTopicCanNoLongerBeChanged;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This topic does not offer a pin preference.'**
  String get thisTopicDoesNotOfferAPinPreference;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Another pin change is still finishing.'**
  String get anotherPinChangeIsStillFinishing;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This message can no longer be moved.'**
  String get thisMessageCanNoLongerBeMoved;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Another inbox action is still finishing.'**
  String get anotherInboxActionIsStillFinishing;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The account has changed.'**
  String get theAccountHasChanged;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This topic can no longer be changed that way.'**
  String get thisTopicCanNoLongerBeChangedThatWay;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Another topic action is still finishing.'**
  String get anotherTopicActionIsStillFinishing;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This topic cannot be deleted.'**
  String get thisTopicCannotBeDeleted;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This topic cannot be recovered.'**
  String get thisTopicCannotBeRecovered;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load this topic\'\'s summary.'**
  String get couldnTLoadThisTopicSSummary;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This post can no longer be edited.'**
  String get thisPostCanNoLongerBeEdited;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open the full editor to edit localized content.'**
  String get openTheFullEditorToEditLocalizedContent;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The selected text could not be matched safely.'**
  String get theSelectedTextCouldNotBeMatchedSafely;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Another action on this post is still being saved.'**
  String get anotherActionOnThisPostIsStillBeingSaved;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The topic changed before the edit could be saved.'**
  String get theTopicChangedBeforeTheEditCouldBeSaved;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This topic can no longer be edited.'**
  String get thisTopicCanNoLongerBeEdited;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'A topic title is required.'**
  String get aTopicTitleIsRequired;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The forum changed before the title saved.'**
  String get theForumChangedBeforeTheTitleSaved;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The forum changed before the category saved.'**
  String get theForumChangedBeforeTheCategorySaved;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic tags can no longer be edited.'**
  String get topicTagsCanNoLongerBeEdited;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The site changed before tags were saved.'**
  String get theSiteChangedBeforeTagsWereSaved;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'More emoji'**
  String get moreEmoji;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Your connection changed. Reopen Move posts and try again.'**
  String get yourConnectionChangedReopenMovePostsAndTryAgain;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Your connection changed. Reopen Change owner and try again.'**
  String get yourConnectionChangedReopenChangeOwnerAndTryAgain;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Your connection changed. Reopen the action and try again.'**
  String get yourConnectionChangedReopenTheActionAndTryAgain;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This post cannot be permanently deleted.'**
  String get thisPostCannotBePermanentlyDeleted;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This post cannot be permanently deleted yet.'**
  String get thisPostCannotBePermanentlyDeletedYet;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Your connection changed. Reopen the post notice and try again.'**
  String get yourConnectionChangedReopenThePostNoticeAndTryAgain;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This post notice can no longer be edited.'**
  String get thisPostNoticeCanNoLongerBeEdited;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This post can no longer be flagged.'**
  String get thisPostCanNoLongerBeFlagged;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Your connection changed. Reopen the flag form and try again.'**
  String get yourConnectionChangedReopenTheFlagFormAndTryAgain;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This topic can no longer be flagged.'**
  String get thisTopicCanNoLongerBeFlagged;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Another flag on this topic is still being saved.'**
  String get anotherFlagOnThisTopicIsStillBeingSaved;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Another post action is still finishing.'**
  String get anotherPostActionIsStillFinishing;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to this forum to bookmark it.'**
  String get reconnectToThisForumToBookmarkIt;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This bookmark target requires its owning context.'**
  String get thisBookmarkTargetRequiresItsOwningContext;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This bookmark target is not available in this build.'**
  String get thisBookmarkTargetIsNotAvailableInThisBuild;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Another action on this bookmark is still finishing.'**
  String get anotherActionOnThisBookmarkIsStillFinishing;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The forum changed before the bookmark finished.'**
  String get theForumChangedBeforeTheBookmarkFinished;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t confirm whether the bookmark was created. The {refreshTarget} is being refreshed.'**
  String couldnTConfirmWhetherTheBookmarkWasCreatedTheIsBeing(
    String refreshTarget,
  );

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The bookmark was saved on the forum.'**
  String get theBookmarkWasSavedOnTheForum;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This bookmark cannot be edited here.'**
  String get thisBookmarkCannotBeEditedHere;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t confirm the bookmark changes. The {refreshTarget} is being refreshed.'**
  String couldnTConfirmTheBookmarkChangesTheIsBeingRefreshed(
    String refreshTarget,
  );

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The bookmark was updated on the forum.'**
  String get theBookmarkWasUpdatedOnTheForum;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This bookmark cannot be deleted here.'**
  String get thisBookmarkCannotBeDeletedHere;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t confirm the deletion. The {refreshTarget} is being refreshed.'**
  String couldnTConfirmTheDeletionTheIsBeingRefreshed(String refreshTarget);

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The bookmark was deleted on the forum.'**
  String get theBookmarkWasDeletedOnTheForum;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to this forum to delete its bookmarks.'**
  String get reconnectToThisForumToDeleteItsBookmarks;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Another bookmark action is still finishing.'**
  String get anotherBookmarkActionIsStillFinishing;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The forum changed before the bookmarks were deleted.'**
  String get theForumChangedBeforeTheBookmarksWereDeleted;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t confirm the deletion. The topic is being refreshed.'**
  String get couldnTConfirmTheDeletionTheTopicIsBeingRefreshed;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t see who liked this.'**
  String get couldnTSeeWhoLikedThis;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load who liked this.'**
  String get couldnTLoadWhoLikedThis;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Upload cancelled.'**
  String get uploadCancelled;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t prepare this post. Nothing was posted.'**
  String get couldnTPrepareThisPostNothingWasPosted;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t reach the site. Nothing was posted.'**
  String get couldnTReachTheSiteNothingWasPosted;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Please add details and specifics to your topic by editing the topic template.'**
  String get pleaseAddDetailsAndSpecificsToYourTopicByEditingThe;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You must choose a category.'**
  String get youMustChooseACategory;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t see that profile.'**
  String get couldnTSeeThatProfile;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load @{username}.'**
  String couldnTLoadShellcontroller(String username);

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load tags from {instanceHost}.'**
  String couldnTLoadTagsFrom(String instanceHost);

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load categories from {instanceHost}.'**
  String couldnTLoadCategoriesFrom(String instanceHost);

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load more categories from {instanceHost}.'**
  String couldnTLoadMoreCategoriesFrom(String instanceHost);

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get summary;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Plugin {consumer} cannot use emoji context {contextId}.'**
  String pluginCannotUseEmojiContext(String consumer, String contextId);

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Plugin {consumer} cannot inspect plugin data owned by {keyOwner}.'**
  String pluginCannotInspectPluginDataOwnedBy(String consumer, String keyOwner);

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Plugin {consumer} cannot inspect current-user data owned by {keyOwner}.'**
  String pluginCannotInspectCurrentUserDataOwnedBy(
    String consumer,
    String keyOwner,
  );

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Plugin {consumer} cannot update plugin data owned by {keyOwner}.'**
  String pluginCannotUpdatePluginDataOwnedBy(String consumer, String keyOwner);

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Plugin {consumer} cannot request bookmark target {targetTypeId}.'**
  String pluginCannotRequestBookmarkTarget(
    String consumer,
    String targetTypeId,
  );

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This bookmark does not belong to {targetTypeRefreshLabel}.'**
  String thisBookmarkDoesNotBelongTo(String targetTypeRefreshLabel);

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'did not register notification feed'**
  String get didNotRegisterNotificationFeed;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'cannot access notification feed'**
  String get cannotAccessNotificationFeed;

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Plugin {consumer} {reason} {idId}.'**
  String plugin(String consumer, String reason, String idId);

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Plugin {consumer} must use its registered notification feed {sourceIdId}.'**
  String pluginMustUseItsRegisteredNotificationFeed(
    String consumer,
    String sourceIdId,
  );

  /// English UI message used by shell/shell_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Plugin {consumer} did not register dismissal for notification feed {sourceIdId}.'**
  String pluginDidNotRegisterDismissalForNotificationFeed(
    String consumer,
    String sourceIdId,
  );

  /// English UI message used by shell/tags_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No tags yet'**
  String get noTagsYet;

  /// English UI message used by shell/emoji_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The composer changed while the emoji picker was open. Nothing was changed.'**
  String get theComposerChangedWhileTheEmojiPickerWasOpenNothingWas;

  /// English UI message used by shell/aggregate_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No forums selected'**
  String get noForumsSelected;

  /// English UI message used by shell/aggregate_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No matching topics'**
  String get noMatchingTopics;

  /// English UI message used by shell/aggregate_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose forums'**
  String get chooseForums;

  /// English UI message used by shell/aggregate_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Forum filters'**
  String get forumFilters;

  /// English UI message used by shell/aggregate_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit active filters'**
  String get editActiveFilters;

  /// English UI message used by shell/aggregate_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Use forum default'**
  String get useForumDefault;

  /// English UI message used by shell/aggregate_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Aggregate'**
  String get aggregate;

  /// English UI message used by shell/aggregate_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Aggregate {index}'**
  String aggregateAggregateview(String index);

  /// English UI message used by shell/aggregate_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Aggregate tab'**
  String get aggregateTab;

  /// English UI message used by shell/aggregate_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This forum already has 20 tabs. Close one and try again.'**
  String get thisForumAlreadyHas20TabsCloseOneAndTryAgain;

  /// English UI message used by shell/aggregate_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'That topic is no longer available.'**
  String get thatTopicIsNoLongerAvailable;

  /// English UI message used by shell/aggregate_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{failed, plural, =1{{failed} forum could not be refreshed.} other{{failed} forums could not be refreshed.}}'**
  String notBeRefreshed(num failed);

  /// English UI message used by shell/group/group_activity_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Posts'**
  String get posts;

  /// English UI message used by shell/group/group_activity_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Group activity'**
  String get groupActivity;

  /// English UI message used by shell/group/group_activity_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topics are not available yet.'**
  String get topicsAreNotAvailableYet;

  /// English UI message used by shell/group/group_activity_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No {kind} yet.'**
  String noYet(String kind);

  /// English UI message used by shell/group/group_activity_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'There are no pending membership requests.'**
  String get thereAreNoPendingMembershipRequests;

  /// English UI message used by shell/group/group_activity_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// English UI message used by shell/group/group_activity_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get deny;

  /// English UI message used by shell/group/group_activity_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get inbox;

  /// English UI message used by shell/group/group_activity_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archive;

  /// English UI message used by shell/group/group_activity_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Messages are not available yet.'**
  String get messagesAreNotAvailableYet;

  /// English UI message used by shell/group/group_activity_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Group messages'**
  String get groupMessages;

  /// English UI message used by shell/group/group_activity_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'There are no categories associated with this group.'**
  String get thereAreNoCategoriesAssociatedWithThisGroup;

  /// English UI message used by shell/group/group_activity_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Create, reply, and see'**
  String get createReplyAndSee;

  /// English UI message used by shell/group/group_activity_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reply and see'**
  String get replyAndSee;

  /// English UI message used by shell/group/group_activity_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'See'**
  String get seeGroupactivityview;

  /// English UI message used by shell/group/group_activity_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Custom access'**
  String get customAccess;

  /// English UI message used by shell/group/group_shared_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Logged-in users'**
  String get loggedInUsers;

  /// English UI message used by shell/group/group_shared_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Group members'**
  String get groupMembers;

  /// English UI message used by shell/group/group_shared_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Group owners'**
  String get groupOwners;

  /// English UI message used by shell/group/group_shared_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get staff;

  /// English UI message used by shell/group/group_shared_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Nobody'**
  String get nobody;

  /// English UI message used by shell/group/group_shared_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Level {value}'**
  String level(String value);

  /// English UI message used by shell/group/group_shared_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Group changed'**
  String get groupChanged;

  /// English UI message used by shell/group/group_manage_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter a group name.'**
  String get enterAGroupName;

  /// English UI message used by shell/group/group_manage_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t save that group change.'**
  String get couldnTSaveThatGroupChange;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add members'**
  String get addMembers;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invite to group'**
  String get inviteToGroup;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This group’s members are private.'**
  String get thisGroupSMembersArePrivate;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This group has no members.'**
  String get thisGroupHasNoMembers;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No members match “{filter}”.'**
  String noMembersMatch(String filter);

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading more members'**
  String get loadingMoreMembers;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search members'**
  String get searchMembers;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get added;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Last post'**
  String get lastPost;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Last seen'**
  String get lastSeen;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Sorted ascending'**
  String get sortedAscendingGroupmembersview;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Sorted descending'**
  String get sortedDescendingGroupmembersview;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Sort by {label}'**
  String sortBy(String label);

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Primary'**
  String get primary;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Posted'**
  String get posted;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Seen'**
  String get seen;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove @{memberUsername}?'**
  String removeGroupmembersview(String memberUsername);

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This member will lose access granted by {groupLabel}.'**
  String thisMemberWillLoseAccessGrantedBy(String groupLabel);

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The member could not be updated.'**
  String get theMemberCouldNotBeUpdated;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Manage @{memberUsername}'**
  String manageGroupmembersview(String memberUsername);

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Make owner'**
  String get makeOwner;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove as owner'**
  String get removeAsOwner;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Make primary group'**
  String get makePrimaryGroup;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove as primary group'**
  String get removeAsPrimaryGroup;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove from group'**
  String get removeFromGroup;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Username or email address'**
  String get usernameOrEmailAddress;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Matching users and email address'**
  String get matchingUsersAndEmailAddress;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Type at least two characters.'**
  String get typeAtLeastTwoCharacters;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No matching users.'**
  String get noMatchingUsers;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add by email address'**
  String get addByEmailAddress;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invitation sent to {normalizedEmail}.'**
  String invitationSentTo(String normalizedEmail);

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter an email to send an invitation, or leave it blank to create a one-use link.'**
  String get enterAnEmailToSendAnInvitationOrLeaveItBlank;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Email (optional)'**
  String get emailOptional;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Message (optional)'**
  String get messageOptional;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Copy invite link'**
  String get copyInviteLink;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invite link copied.'**
  String get inviteLinkCopied;

  /// English UI message used by shell/group/group_members_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Create link'**
  String get createLink;

  /// English UI message used by shell/group/group_members_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Members could not be searched. Try again.'**
  String get membersCouldNotBeSearchedTryAgain;

  /// English UI message used by shell/group/group_members_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The selected members could not be added.'**
  String get theSelectedMembersCouldNotBeAdded;

  /// English UI message used by shell/group/group_members_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Not added: {resultSkippedUsernamesJoin}'**
  String notAdded(String resultSkippedUsernamesJoin);

  /// English UI message used by shell/group/group_members_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The invitation could not be created.'**
  String get theInvitationCouldNotBeCreated;

  /// English UI message used by shell/group/group_members_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The server did not return an invite link.'**
  String get theServerDidNotReturnAnInviteLink;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You cannot manage this group.'**
  String get youCannotManageThisGroup;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Interaction'**
  String get interaction;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categories;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get logs;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Group settings'**
  String get groupSettings;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose who can discover and join this group.'**
  String get chooseWhoCanDiscoverAndJoinThisGroup;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Who can join?'**
  String get whoCanJoin;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invitation only'**
  String get invitationOnly;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Request approval'**
  String get requestApproval;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Anyone can join'**
  String get anyoneCanJoin;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Members can leave'**
  String get membersCanLeave;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Group visibility'**
  String get groupVisibility;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Member-list visibility'**
  String get memberListVisibility;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Request template'**
  String get requestTemplate;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Automatic membership email domains'**
  String get automaticMembershipEmailDomains;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Associated group IDs'**
  String get associatedGroupIDs;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Grant trust level'**
  String get grantTrustLevel;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Control mentions, messages, and notification defaults.'**
  String get controlMentionsMessagesAndNotificationDefaults;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Who can mention this group?'**
  String get whoCanMentionThisGroup;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Who can message this group?'**
  String get whoCanMessageThisGroup;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Default notification level'**
  String get defaultNotificationLevel;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Publish read state'**
  String get publishReadState;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Let members share message read state.'**
  String get letMembersShareMessageReadState;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Incoming email address'**
  String get incomingEmailAddress;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Configure the mailbox used by this group.'**
  String get configureTheMailboxUsedByThisGroup;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enable SMTP'**
  String get enableSMTP;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get port;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to keep the existing password'**
  String get leaveBlankToKeepTheExistingPassword;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'From alias'**
  String get fromAlias;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Allow replies from unknown senders'**
  String get allowRepliesFromUnknownSenders;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Category notifications'**
  String get categoryNotifications;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter comma-separated category IDs for each level.'**
  String get enterCommaSeparatedCategoryIDsForEachLevel;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Tag notifications'**
  String get tagNotifications;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter comma-separated tag names for each level.'**
  String get enterCommaSeparatedTagNamesForEachLevel;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The name and identity people see around the forum.'**
  String get theNameAndIdentityPeopleSeeAroundTheForum;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get fullName;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'About this group'**
  String get aboutThisGroup;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Member title'**
  String get memberTitle;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Flair icon'**
  String get flairIcon;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Flair background'**
  String get flairBackground;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Flair foreground'**
  String get flairForeground;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No group changes have been recorded.'**
  String get noGroupChangesHaveBeenRecorded;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Membership and settings changes for this group.'**
  String get membershipAndSettingsChangesForThisGroup;

  /// English UI message used by shell/topic_category_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove category'**
  String get removeCategory;

  /// English UI message used by shell/invite_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t copy the invite link.'**
  String get couldnTCopyTheInviteLink;

  /// English UI message used by shell/invite_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invitation email sent.'**
  String get invitationEmailSent;

  /// English UI message used by shell/invite_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invite link created.'**
  String get inviteLinkCreated;

  /// English UI message used by shell/invite_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Copied!'**
  String get copiedInviteeditor;

  /// English UI message used by shell/invite_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Back to invites'**
  String get backToInvites;

  /// English UI message used by shell/invite_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Create invite'**
  String get createInvite;

  /// English UI message used by shell/invite_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Leave blank for a shareable link.'**
  String get leaveBlankForAShareableLink;

  /// English UI message used by shell/invite_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get enterAValidEmailAddress;

  /// English UI message used by shell/invite_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get descriptionOptional;

  /// English UI message used by shell/invite_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Maximum uses'**
  String get maximumUses;

  /// English UI message used by shell/invite_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Up to {limit}'**
  String upTo(String limit);

  /// English UI message used by shell/invite_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter a number from 1 to {limit}.'**
  String enterANumberFrom1To(String limit);

  /// English UI message used by shell/invite_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Expires after (days)'**
  String get expiresAfterDays;

  /// English UI message used by shell/invite_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter a number from 1 to 36500.'**
  String get enterANumberFrom1To36500;

  /// English UI message used by shell/invite_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Send invitation email'**
  String get sendInvitationEmail;

  /// English UI message used by shell/invite_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Custom message (optional)'**
  String get customMessageOptional;

  /// English UI message used by shell/invite_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Creating…'**
  String get creating;

  /// English UI message used by shell/invite_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Create and send email'**
  String get createAndSendEmail;

  /// English UI message used by shell/invite_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Create invite link'**
  String get createInviteLink;

  /// English UI message used by shell/composer_link.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get link;

  /// English UI message used by shell/composer_link.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit link to {url}'**
  String editLinkTo(String url);

  /// English UI message used by shell/composer_link.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Insert link'**
  String get insertLink;

  /// English UI message used by shell/composer_link.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get text;

  /// English UI message used by shell/topic_row_content.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get pinned;

  /// English UI message used by shell/topic_row_content.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Bookmarked'**
  String get bookmarked;

  /// English UI message used by shell/topic_row_content.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic has new replies'**
  String get topicHasNewReplies;

  /// English UI message used by shell/topic_change_owner.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Change post owner'**
  String get changePostOwner;

  /// English UI message used by shell/topic_change_owner.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Assign {count} post by @{oldUsername} to another account.} other{Assign {count} posts by @{oldUsername} to another account.}}'**
  String assignByToAnotherAccount(num count, String oldUsername);

  /// English UI message used by shell/topic_change_owner.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search users'**
  String get searchUsers;

  /// English UI message used by shell/topic_change_owner.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search for the new owner.'**
  String get searchForTheNewOwner;

  /// English UI message used by shell/topic_change_owner.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No users found.'**
  String get noUsersFound;

  /// English UI message used by shell/topic_change_owner.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Change owner'**
  String get changeOwner;

  /// English UI message used by shell/groups_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search groups'**
  String get searchGroups;

  /// English UI message used by shell/groups_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get newGroup;

  /// English UI message used by shell/groups_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Filter by group type'**
  String get filterByGroupType;

  /// English UI message used by shell/groups_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'All groups'**
  String get allGroups;

  /// English UI message used by shell/groups_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'My groups'**
  String get myGroups;

  /// English UI message used by shell/groups_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Groups I own'**
  String get groupsIOwn;

  /// English UI message used by shell/groups_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Public groups'**
  String get publicGroups;

  /// English UI message used by shell/groups_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Closed groups'**
  String get closedGroups;

  /// English UI message used by shell/groups_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Automatic groups'**
  String get automaticGroups;

  /// English UI message used by shell/groups_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Members hidden'**
  String get membersHidden;

  /// English UI message used by shell/groups_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No groups match these filters.'**
  String get noGroupsMatchTheseFilters;

  /// English UI message used by shell/global_search_models.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topics & posts'**
  String get topicsPosts;

  /// English UI message used by shell/choice_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No matching options.'**
  String get noMatchingOptions;

  /// English UI message used by shell/choice_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dismiss {title}'**
  String dismissChoicemenu(String title);

  /// English UI message used by shell/choice_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Clear filter'**
  String get clearFilter;

  /// English UI message used by shell/choice_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choices'**
  String get choices;

  /// English UI message used by shell/anonymous_flag_dialog.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Illegal content: {topicTitle}'**
  String illegalContent(String topicTitle);

  /// English UI message used by shell/anonymous_flag_dialog.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This post {postUrl} contains illegal content.'**
  String thisPostContainsIllegalContent(String postUrl);

  /// English UI message used by shell/anonymous_flag_dialog.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Report illegal content'**
  String get reportIllegalContent;

  /// English UI message used by shell/anonymous_flag_dialog.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This site accepts illegal-content reports by email. Your mail application will open with the post link and subject filled in.'**
  String get thisSiteAcceptsIllegalContentReportsByEmailYourMailApplication;

  /// English UI message used by shell/anonymous_flag_dialog.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open email'**
  String get openEmail;

  /// English UI message used by shell/anonymous_flag_dialog.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t open a mail application.'**
  String get couldnTOpenAMailApplication;

  /// English UI message used by shell/topic_title.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit topic title'**
  String get editTopicTitle;

  /// English UI message used by shell/video_download.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The video could not be downloaded.'**
  String get theVideoCouldNotBeDownloaded;

  /// English UI message used by shell/composer_upload_attachment.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t upload this image.'**
  String get couldnTUploadThisImage;

  /// English UI message used by shell/composer_upload_attachment.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Uploaded'**
  String get uploaded;

  /// English UI message used by shell/composer_upload_attachment.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Processing image'**
  String get processingImage;

  /// English UI message used by shell/composer_upload_attachment.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Retrying'**
  String get retrying;

  /// English UI message used by shell/composer_upload_attachment.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Uploading'**
  String get uploading;

  /// English UI message used by shell/composer_upload_attachment.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Retry upload'**
  String get retryUpload;

  /// English UI message used by shell/composer_upload_attachment.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove upload'**
  String get removeUpload;

  /// English UI message used by shell/composer_upload_attachment.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Cancel upload'**
  String get cancelUpload;

  /// English UI message used by shell/composer_upload_attachment.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Preview of {filename}'**
  String previewOf(String filename);

  /// English UI message used by shell/resizable_pane.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{valueRound} pixels wide'**
  String pixelsWide(String valueRound);

  /// English UI message used by shell/topic_list_navigation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic lists'**
  String get topicLists;

  /// English UI message used by shell/topic_list_navigation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'New · Topics'**
  String get newTopics;

  /// English UI message used by shell/topic_list_navigation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'New · Replies'**
  String get newReplies;

  /// English UI message used by shell/topic_list_navigation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unseen'**
  String get unseen;

  /// English UI message used by shell/topic_list_navigation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Trending'**
  String get trending;

  /// English UI message used by shell/topic_list_navigation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Top · {modeTopPeriodLabel}'**
  String top(String modeTopPeriodLabel);

  /// English UI message used by shell/topic_list_navigation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Replies'**
  String get replies;

  /// English UI message used by shell/topic_list_navigation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose topic feed'**
  String get chooseTopicFeed;

  /// English UI message used by shell/topic_list_navigation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'New activity'**
  String get newActivity;

  /// English UI message used by shell/topic_list_navigation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Top'**
  String get topTopiclistnavigation;

  /// English UI message used by shell/topic_list_navigation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Top periods'**
  String get topPeriods;

  /// English UI message used by shell/global_search_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search {scopeLabel}'**
  String searchGlobalsearchpanel(String scopeLabel);

  /// English UI message used by shell/global_search_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// English UI message used by shell/global_search_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Clear all search conditions'**
  String get clearAllSearchConditions;

  /// English UI message used by shell/global_search_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Keep typing'**
  String get keepTyping;

  /// English UI message used by shell/global_search_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter at least {controllerCapabilitiesMinimumLength} characters to search.'**
  String enterAtLeastCharactersToSearch(
    String controllerCapabilitiesMinimumLength,
  );

  /// English UI message used by shell/global_search_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search could not load'**
  String get searchCouldNotLoad;

  /// English UI message used by shell/global_search_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Please try again.'**
  String get pleaseTryAgain;

  /// English UI message used by shell/global_search_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get noResultsFound;

  /// English UI message used by shell/global_search_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Try different words or remove a condition.'**
  String get tryDifferentWordsOrRemoveACondition;

  /// English UI message used by shell/global_search_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get viewAll;

  /// English UI message used by shell/global_search_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'View all {sectionScopeLabel} results'**
  String viewAllResults(String sectionScopeLabel);

  /// English UI message used by shell/global_search_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Recent searches'**
  String get recentSearches;

  /// English UI message used by shell/global_search_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get clearHistory;

  /// English UI message used by shell/global_search_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Clear conditions'**
  String get clearConditions;

  /// English UI message used by shell/global_search_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Personal message'**
  String get personalMessage;

  /// English UI message used by shell/global_search_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Ordering and display'**
  String get orderingAndDisplay;

  /// English UI message used by shell/global_search_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Ordering'**
  String get ordering;

  /// English UI message used by shell/global_search_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Order search results'**
  String get orderSearchResults;

  /// English UI message used by shell/global_search_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Ascending'**
  String get ascending;

  /// English UI message used by shell/global_search_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Ascending order'**
  String get ascendingOrder;

  /// English UI message used by shell/global_search_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Display properties'**
  String get displayProperties;

  /// English UI message used by shell/global_search_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Excerpt'**
  String get excerpt;

  /// English UI message used by shell/global_search_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get author;

  /// English UI message used by shell/global_search_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Likes'**
  String get likes;

  /// English UI message used by shell/post_flag_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Flag Topic'**
  String get flagTopic;

  /// English UI message used by shell/post_flag_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Flag Post'**
  String get flagPost;

  /// English UI message used by shell/post_flag_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Message to @{username}'**
  String messageTo(String username);

  /// English UI message used by shell/post_flag_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Describe the illegal content'**
  String get describeTheIllegalContent;

  /// English UI message used by shell/post_flag_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Message to the moderators'**
  String get messageToTheModerators;

  /// English UI message used by shell/post_flag_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Explain constructively how this {targetNoun} can be improved.'**
  String explainConstructivelyHowThisCanBeImproved(String targetNoun);

  /// English UI message used by shell/post_flag_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Explain precisely what is illegal about this {targetNoun}.'**
  String explainPreciselyWhatIsIllegalAboutThis(String targetNoun);

  /// English UI message used by shell/post_flag_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Explain why this {targetNoun} needs moderator attention.'**
  String explainWhyThisNeedsModeratorAttention(String targetNoun);

  /// English UI message used by shell/post_flag_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{minimumMessageLengthLength} more required · {postFlagTypeMaximumMessageLengthLength} remaining'**
  String moreRequiredRemaining(
    String minimumMessageLengthLength,
    String postFlagTypeMaximumMessageLengthLength,
  );

  /// English UI message used by shell/post_flag_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'All flags are received by moderators and will be reviewed as soon as possible.'**
  String get allFlagsAreReceivedByModeratorsAndWillBeReviewedAs;

  /// English UI message used by shell/post_flag_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'What I’ve written above is accurate and complete'**
  String get whatIVeWrittenAboveIsAccurateAndComplete;

  /// English UI message used by shell/user_activity.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Connect this account to see its activity'**
  String get connectThisAccountToSeeItsActivity;

  /// English UI message used by shell/user_activity.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get noActivityYet;

  /// English UI message used by shell/user_activity.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topics you create and replies you post will appear here. Likes, bookmarks, reads, and drafts have their own lists.'**
  String get topicsYouCreateAndRepliesYouPostWillAppearHereLikes;

  /// English UI message used by shell/user_activity.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading more activity'**
  String get loadingMoreActivity;

  /// English UI message used by shell/user_activity.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic created by {itemUsername}'**
  String topicCreatedBy(String itemUsername);

  /// English UI message used by shell/user_activity.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reply by {itemUsername}'**
  String replyBy(String itemUsername);

  /// English UI message used by shell/user_activity.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Post {itemPostNumber}'**
  String postUseractivity(String itemPostNumber);

  /// English UI message used by shell/user_activity.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get deleted;

  /// English UI message used by shell/user_activity.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get hidden;

  /// English UI message used by shell/user_activity.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading activity'**
  String get loadingActivity;

  /// English UI message used by shell/forum_settings_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get display;

  /// English UI message used by shell/forum_settings_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Themes'**
  String get themes;

  /// English UI message used by shell/forum_settings_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get accessibility;

  /// English UI message used by shell/composer_selection_colors.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Gray'**
  String get gray;

  /// English UI message used by shell/composer_selection_colors.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Brown'**
  String get brown;

  /// English UI message used by shell/composer_selection_colors.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get orange;

  /// English UI message used by shell/composer_selection_colors.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Yellow'**
  String get yellow;

  /// English UI message used by shell/composer_selection_colors.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get green;

  /// English UI message used by shell/composer_selection_colors.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get blue;

  /// English UI message used by shell/composer_selection_colors.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Purple'**
  String get purple;

  /// English UI message used by shell/composer_selection_colors.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get pink;

  /// English UI message used by shell/composer_selection_colors.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get red;

  /// English UI message used by shell/composer_selection_colors.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get background;

  /// English UI message used by shell/composer_selection_colors.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Text and background colors'**
  String get textAndBackgroundColors;

  /// English UI message used by shell/composer_selection_colors.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Background color'**
  String get backgroundColor;

  /// English UI message used by shell/composer_selection_colors.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Text color'**
  String get textColor;

  /// English UI message used by shell/composer_selection_colors.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get color;

  /// English UI message used by shell/desktop_panels.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Minimize panel'**
  String get minimizePanel;

  /// English UI message used by shell/desktop_panels.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open a tab in the other panel first'**
  String get openATabInTheOtherPanelFirst;

  /// English UI message used by shell/desktop_panels.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Main panel, minimized'**
  String get mainPanelMinimized;

  /// English UI message used by shell/desktop_panels.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Secondary panel, minimized'**
  String get secondaryPanelMinimized;

  /// English UI message used by shell/desktop_panels.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Resize main panel'**
  String get resizeMainPanel;

  /// English UI message used by shell/desktop_panels.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Main panel'**
  String get mainPanel;

  /// English UI message used by shell/desktop_panels.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Secondary panel'**
  String get secondaryPanel;

  /// English UI message used by shell/desktop_panels.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Drop this tab here'**
  String get dropThisTabHere;

  /// English UI message used by shell/desktop_panels.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Drag a tab here or open a new tab.'**
  String get dragATabHereOrOpenANewTab;

  /// English UI message used by shell/cooked_html.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'1px solid {horizontalRuleColor}'**
  String message1pxSolid(String horizontalRuleColor);

  /// English UI message used by shell/cooked_html.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'link clicked 1 time'**
  String get linkClicked1Time;

  /// English UI message used by shell/cooked_html.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'link clicked {count} times'**
  String linkClickedTimes(String count);

  /// English UI message used by shell/cooked_html.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'header a[href]'**
  String get headerAHref;

  /// English UI message used by shell/topic_header_tags.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add tag'**
  String get addTag;

  /// English UI message used by shell/topic_header_tags.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Saving tags'**
  String get savingTags;

  /// English UI message used by shell/topic_header_tags.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Tags · {tagsLength}'**
  String tagsTopicheadertags(String tagsLength);

  /// English UI message used by shell/topic_header_tags.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic tags'**
  String get topicTags;

  /// English UI message used by shell/topic_header_tags.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit topic tags: {tagsIndexName}'**
  String editTopicTags(String tagsIndexName);

  /// English UI message used by shell/topic_header_tags.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open tag {tagsIndexName}'**
  String openTagTopicheadertags(String tagsIndexName);

  /// English UI message used by shell/topic_header_tags.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'View and edit all {tagsLength} topic tags'**
  String viewAndEditAllTopicTags(String tagsLength);

  /// English UI message used by shell/topic_header_tags.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'View all {tagsLength} topic tags'**
  String viewAllTopicTags(String tagsLength);

  /// English UI message used by shell/topic_header_tags.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add or remove topic tags'**
  String get addOrRemoveTopicTags;

  /// English UI message used by shell/topic_header_tags.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Find a topic tag'**
  String get findATopicTag;

  /// English UI message used by shell/topic_header_tags.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No matching tags'**
  String get noMatchingTagsTopicheadertags;

  /// English UI message used by shell/composer_details.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Details editor'**
  String get detailsEditor;

  /// English UI message used by shell/composer_details.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Details summary'**
  String get detailsSummary;

  /// English UI message used by shell/composer_details.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Details content'**
  String get detailsContent;

  /// English UI message used by shell/composer_details.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Write here…'**
  String get writeHere;

  /// English UI message used by shell/composer_details.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove details, keep content'**
  String get removeDetailsKeepContent;

  /// English UI message used by shell/composer_details.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Delete details'**
  String get deleteDetails;

  /// English UI message used by shell/composer_details.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Collapse details'**
  String get collapseDetails;

  /// English UI message used by shell/composer_details.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Expand details'**
  String get expandDetails;

  /// English UI message used by shell/invite_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invites are unavailable for this account.'**
  String get invitesAreUnavailableForThisAccount;

  /// English UI message used by shell/invite_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search invites'**
  String get searchInvites;

  /// English UI message used by shell/invite_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Email or username'**
  String get emailOrUsername;

  /// English UI message used by shell/invite_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading invites'**
  String get loadingInvites;

  /// English UI message used by shell/invite_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No matching invites.'**
  String get noMatchingInvites;

  /// English UI message used by shell/invite_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Manage invites in browser'**
  String get manageInvitesInBrowser;

  /// English UI message used by shell/invite_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Restricted to {inviteDomain}'**
  String restrictedToInvitelist(String inviteDomain);

  /// English UI message used by shell/invite_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get expired;

  /// English UI message used by shell/invite_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Expires'**
  String get expires;

  /// English UI message used by shell/invite_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invited via {inviteInviteSource}'**
  String invitedVia(String inviteInviteSource);

  /// English UI message used by shell/invite_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove this invite? It will no longer be usable.'**
  String get removeThisInviteItWillNoLongerBeUsable;

  /// English UI message used by shell/invite_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Confirm removal'**
  String get confirmRemoval;

  /// English UI message used by shell/invite_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Resend'**
  String get resend;

  /// English UI message used by shell/oneboxes/twitter.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Replying to a post'**
  String get replyingToAPost;

  /// English UI message used by shell/oneboxes/twitter.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get follow;

  /// English UI message used by shell/oneboxes/twitter.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Follow @{handle} on X'**
  String followOnX(String handle);

  /// English UI message used by shell/oneboxes/twitter.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'View post on X'**
  String get viewPostOnX;

  /// English UI message used by shell/oneboxes/twitter.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not copy link. Try again.'**
  String get couldNotCopyLinkTryAgain;

  /// English UI message used by shell/oneboxes/twitter.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{metricLabelLikesLike}. Like on X'**
  String likeOnX(String metricLabelLikesLike);

  /// English UI message used by shell/oneboxes/twitter.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{metricLabelRepostsRepost}. View post on X'**
  String viewPostOnXTwitter(String metricLabelRepostsRepost);

  /// English UI message used by shell/oneboxes/twitter.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Read replies'**
  String get readReplies;

  /// English UI message used by shell/oneboxes/reddit.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{comment, select, true{Reddit comment · {path}/{pathValue3}} other{Reddit post · {path}/{pathValue3}}}'**
  String reddit(String comment, String path, String pathValue3);

  /// English UI message used by shell/oneboxes/reddit.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open on Reddit'**
  String get openOnReddit;

  /// English UI message used by shell/oneboxes/audio.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get audio;

  /// English UI message used by shell/oneboxes/forum_theme.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This shared theme is incomplete or invalid. Ask for a new copy.'**
  String get thisSharedThemeIsIncompleteOrInvalidAskForANew;

  /// English UI message used by shell/oneboxes/forum_theme.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not save theme. Try again.'**
  String get couldNotSaveThemeTryAgain;

  /// English UI message used by shell/oneboxes/forum_theme.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{themeName} forum appearance preview'**
  String forumAppearancePreview(String themeName);

  /// English UI message used by shell/oneboxes/forum_theme.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Custom theme'**
  String get customTheme;

  /// English UI message used by shell/oneboxes/forum_theme.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Theme preview appearance'**
  String get themePreviewAppearance;

  /// English UI message used by shell/oneboxes/forum_theme.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Preview light theme'**
  String get previewLightTheme;

  /// English UI message used by shell/oneboxes/forum_theme.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Light preview'**
  String get lightPreview;

  /// English UI message used by shell/oneboxes/forum_theme.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Preview dark theme'**
  String get previewDarkTheme;

  /// English UI message used by shell/oneboxes/forum_theme.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dark preview'**
  String get darkPreview;

  /// English UI message used by shell/oneboxes/forum_theme.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Using theme'**
  String get usingTheme;

  /// English UI message used by shell/oneboxes/forum_theme.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Use theme'**
  String get useTheme;

  /// English UI message used by shell/oneboxes/forum_theme.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Saving theme'**
  String get savingTheme;

  /// English UI message used by shell/oneboxes/forum_theme.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open this theme in a connected forum.'**
  String get openThisThemeInAConnectedForum;

  /// English UI message used by shell/oneboxes/embedded.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Asciinema recording'**
  String get asciinemaRecording;

  /// English UI message used by shell/oneboxes/embedded.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Load embed'**
  String get loadEmbed;

  /// English UI message used by shell/topic_list_filter_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Subcategories'**
  String get subcategories;

  /// English UI message used by shell/topic_list_filter_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Filter by tag'**
  String get filterByTag;

  /// English UI message used by shell/topic_list_filter_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Filter by tags: {tagNameJoin}'**
  String filterByTags(String tagNameJoin);

  /// English UI message used by shell/topic_list_filter_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Tag: {selectedTagsFirstName}'**
  String tagTopiclistfilterbar(String selectedTagsFirstName);

  /// English UI message used by shell/instance_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove {instanceTitle}?'**
  String removeInstanceactions(String instanceTitle);

  /// English UI message used by shell/instance_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This signs out of {instanceHost} and takes it out of the rail. The app will revoke this device’s access so notifications stop. You can add the forum back at any time.'**
  String thisSignsOutOfAndTakesItOutOfTheRail(String instanceHost);

  /// English UI message used by shell/instance_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t remove {instanceTitle}. Try again.'**
  String couldnTRemoveTryAgain(String instanceTitle);

  /// English UI message used by shell/instance_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Show forum actions'**
  String get showForumActions;

  /// English UI message used by shell/instance_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove forum'**
  String get removeForum;

  /// English UI message used by shell/instance_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'More Options'**
  String get moreOptionsInstanceactions;

  /// English UI message used by shell/instance_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Forum actions'**
  String get forumActions;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Delete this topic action'**
  String get deleteThisTopicAction;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove like'**
  String get removeLike;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Like'**
  String get like;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove your like'**
  String get removeYourLike;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Like this post'**
  String get likeThisPost;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Share this post'**
  String get shareThisPost;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Copy a link to this post to clipboard'**
  String get copyALinkToThisPostToClipboard;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reply to this post'**
  String get replyToThisPost;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit this post'**
  String get editThisPost;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Bookmark this post'**
  String get bookmarkThisPost;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit this post bookmark'**
  String get editThisPostBookmark;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'View edit history'**
  String get viewEditHistory;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'View this post\'\'s edit history'**
  String get viewThisPostSEditHistory;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove wiki'**
  String get removeWiki;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Make wiki'**
  String get makeWiki;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Return this to ordinary post editing'**
  String get returnThisToOrdinaryPostEditing;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Allow community members to edit this post'**
  String get allowCommunityMembersToEditThisPost;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unlock post'**
  String get unlockPost;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Lock post'**
  String get lockPost;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Allow this post to be edited again'**
  String get allowThisPostToBeEditedAgain;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Prevent further edits to this post'**
  String get preventFurtherEditsToThisPost;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Privately flag this post for attention'**
  String get privatelyFlagThisPostForAttention;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Report illegal content by email'**
  String get reportIllegalContentByEmail;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unhide post'**
  String get unhidePost;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Restore this hidden post'**
  String get restoreThisHiddenPost;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Revert to regular post'**
  String get revertToRegularPost;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Convert to moderator post'**
  String get convertToModeratorPost;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove the moderator styling from this post'**
  String get removeTheModeratorStylingFromThisPost;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Mark this as an official moderator post'**
  String get markThisAsAnOfficialModeratorPost;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add post notice'**
  String get addPostNotice;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Change post notice'**
  String get changePostNotice;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add a staff notice above this post'**
  String get addAStaffNoticeAboveThisPost;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Change or remove the staff notice'**
  String get changeOrRemoveTheStaffNotice;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Assign this post to another account'**
  String get assignThisPostToAnotherAccount;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit tags'**
  String get editTags;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit topic tags'**
  String get editTopicTagsPostactions;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete'**
  String get permanentlyDelete;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete this post'**
  String get permanentlyDeleteThisPost;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Undelete'**
  String get undelete;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Put this post back'**
  String get putThisPostBack;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Delete this post'**
  String get deleteThisPost;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Uncategorized'**
  String get uncategorized;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Category {id}'**
  String categoryPostactions(String id);

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get actions;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get moreActions;

  /// English UI message used by shell/post_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'More actions for post {scopePostNumber}'**
  String moreActionsForPost(String scopePostNumber);

  /// English UI message used by shell/image_grid.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Image gallery'**
  String get imageGallery;

  /// English UI message used by shell/image_grid.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Previous image'**
  String get previousImage;

  /// English UI message used by shell/image_grid.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Next image'**
  String get nextImage;

  /// English UI message used by shell/image_grid.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Go to image {number} of {total}'**
  String goToImageOf(String number, String total);

  /// English UI message used by shell/lightbox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open image: {description}'**
  String openImageLightbox(String description);

  /// English UI message used by shell/lightbox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open image'**
  String get openImageLightboxValue;

  /// English UI message used by shell/lightbox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Saved {filename}.'**
  String saved(String filename);

  /// English UI message used by shell/lightbox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t download image.'**
  String get couldnTDownloadImage;

  /// English UI message used by shell/lightbox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reset zoom'**
  String get resetZoom;

  /// English UI message used by shell/lightbox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get downloading;

  /// English UI message used by shell/lightbox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'include subcategories'**
  String get includeSubcategories;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'only these categories'**
  String get onlyTheseCategories;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose categories'**
  String get chooseCategories;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose one or more categories. Multiple categories match any selected category.'**
  String
  get chooseOneOrMoreCategoriesMultipleCategoriesMatchAnySelectedCategory;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'include any'**
  String get includeAny;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'include all'**
  String get includeAll;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'exclude any'**
  String get excludeAny;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'exclude combination'**
  String get excludeCombination;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose tags'**
  String get chooseTags;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Match any tag, every tag, or exclude selected tags.'**
  String get matchAnyTagEveryTagOrExcludeSelectedTags;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Posted by'**
  String get postedBy;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Find posts written by a specific person. Use me for your posts.'**
  String get findPostsWrittenByASpecificPersonUseMeForYour;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Started by'**
  String get startedBy;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Find opening posts written by this person.'**
  String get findOpeningPostsWrittenByThisPerson;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Author’s group'**
  String get authorSGroup;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Find posts written by members of a group whose membership you can view.'**
  String get findPostsWrittenByMembersOfAGroupWhoseMembershipYou;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Group inbox'**
  String get groupInbox;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search personal messages addressed to this group.'**
  String get searchPersonalMessagesAddressedToThisGroup;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search in'**
  String get searchIn;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'By default, results are grouped by topic. Every matching post shows separate results from the same topic.'**
  String get byDefaultResultsAreGroupedByTopicEveryMatchingPostShows;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic titles'**
  String get topicTitles;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Opening posts'**
  String get openingPosts;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Every matching post'**
  String get everyMatchingPost;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Messages & topics'**
  String get messagesTopics;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search the topics and personal messages available to your account.'**
  String get searchTheTopicsAndPersonalMessagesAvailableToYourAccount;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topics and my messages'**
  String get topicsAndMyMessages;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'My personal messages'**
  String get myPersonalMessages;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'One-to-one personal messages'**
  String get oneToOnePersonalMessages;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'My activity'**
  String get myActivity;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Personal'**
  String get personal;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Narrow results using your reading, notification, and posting activity.'**
  String get narrowResultsUsingYourReadingNotificationAndPostingActivity;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Read posts'**
  String get readPosts;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unread posts'**
  String get unreadPosts;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Tracking or watching'**
  String get trackingOrWatching;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Bookmarked posts'**
  String get bookmarkedPosts;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Liked posts'**
  String get likedPosts;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'My posts'**
  String get myPosts;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topics I started'**
  String get topicsIStarted;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic status'**
  String get topicStatus;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open topics are neither closed nor archived.'**
  String get openTopicsAreNeitherClosedNorArchived;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No replies'**
  String get noReplies;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'One participant'**
  String get oneParticipant;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Public categories'**
  String get publicCategories;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Post type'**
  String get postType;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose the type of post to find.'**
  String get chooseTheTypeOfPostToFind;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Regular posts'**
  String get regularPosts;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Wiki posts'**
  String get wikiPosts;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Posts in pinned topics'**
  String get postsInPinnedTopics;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Posts by bots'**
  String get postsByBots;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Posts by people'**
  String get postsByPeople;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Contains'**
  String get contains;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Find posts with images or topics with or without tags.'**
  String get findPostsWithImagesOrTopicsWithOrWithoutTags;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get images;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'At least one tag'**
  String get atLeastOneTag;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No tags'**
  String get noTags;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'File types'**
  String get fileTypes;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter one or more file extensions, separated by commas.'**
  String get enterOneOrMoreFileExtensionsSeparatedByCommas;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Post date'**
  String get postDate;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dates & counts'**
  String get datesCounts;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Match when a post was created.'**
  String get matchWhenAPostWasCreated;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Post count'**
  String get postCount;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Count all posts in the topic, including the opening post.'**
  String get countAllPostsInTheTopicIncludingTheOpeningPost;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Views'**
  String get views;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Match the topic’s view count.'**
  String get matchTheTopicSViewCount;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'en, fr, any, or none'**
  String get enFrAnyOrNone;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter a language code, any for a detected language, or none for posts without one.'**
  String get enterALanguageCodeAnyForADetectedLanguageOrNone;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get french;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get german;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get spanish;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Any detected language'**
  String get anyDetectedLanguage;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No detected language'**
  String get noDetectedLanguage;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Author’s badge'**
  String get authorSBadge;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Badge name or ID'**
  String get badgeNameOrID;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Find posts written by users who hold this badge.'**
  String get findPostsWrittenByUsersWhoHoldThisBadge;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Specific topic'**
  String get specificTopic;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic ID'**
  String get topicID;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search posts within one topic.'**
  String get searchPostsWithinOneTopic;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Category, tag or tag group'**
  String get categoryTagOrTagGroup;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get advanced;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Category, tag, or tag group slug'**
  String get categoryTagOrTagGroupSlug;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Look up a category first, then a tag, then a tag group with this slug.'**
  String get lookUpACategoryFirstThenATagThenATag;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unlisted topics'**
  String get unlistedTopics;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Available when your account can view unlisted topics, including eligible trust level 4 users.'**
  String
  get availableWhenYourAccountCanViewUnlistedTopicsIncludingEligibleTrust;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Include unlisted topics'**
  String get includeUnlistedTopics;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Whispers'**
  String get whispers;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Requires permission to read whispers.'**
  String get requiresPermissionToReadWhispers;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Whisper posts'**
  String get whisperPosts;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'All personal messages'**
  String get allPersonalMessages;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Administrator search across personal messages.'**
  String get administratorSearchAcrossPersonalMessages;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'All users’ personal messages'**
  String get allUsersPersonalMessages;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'User’s personal messages'**
  String get userSPersonalMessages;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Administrator search within the personal messages of this user.'**
  String get administratorSearchWithinThePersonalMessagesOfThisUser;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'is a member of'**
  String get isAMemberOf;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'is not a member of'**
  String get isNotAMemberOf;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Select a group whose membership is visible. Exclusions can contain multiple group names.'**
  String get selectAGroupWhoseMembershipIsVisibleExclusionsCanContainMultiple;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'is exactly'**
  String get isExactly;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Match one exact username, or exclude usernames separated by commas.'**
  String get matchOneExactUsernameOrExcludeUsernamesSeparatedByCommas;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Activity period'**
  String get activityPeriod;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose the time period used for user activity statistics.'**
  String get chooseTheTimePeriodUsedForUserActivityStatistics;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get allTime;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Quarter'**
  String get quarter;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Group type'**
  String get groupType;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Filter group membership or admission. Closed membership does not mean the group is hidden.'**
  String get filterGroupMembershipOrAdmissionClosedMembershipDoesNotMeanThe;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Groups I joined'**
  String get groupsIJoined;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open membership'**
  String get openMembership;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Closed membership'**
  String get closedMembership;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Custom groups'**
  String get customGroups;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Browse automatic groups available to staff.'**
  String get browseAutomaticGroupsAvailableToStaff;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Find groups this person belongs to, where group membership is visible.'**
  String get findGroupsThisPersonBelongsToWhereGroupMembershipIsVisible;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Latest post'**
  String get latestPost;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Oldest post'**
  String get oldestPost;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Newest topic'**
  String get newestTopic;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Oldest topic'**
  String get oldestTopic;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Most viewed'**
  String get mostViewed;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Most liked'**
  String get mostLiked;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Recently read'**
  String get recentlyRead;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Member count'**
  String get memberCount;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Likes received'**
  String get likesReceived;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Likes given'**
  String get likesGiven;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topics viewed'**
  String get topicsViewed;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topics created'**
  String get topicsCreated;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Posts created'**
  String get postsCreated;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Posts read'**
  String get postsRead;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Days visited'**
  String get daysVisited;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This filter is unavailable on this site.'**
  String get thisFilterIsUnavailableOnThisSite;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose a supported condition.'**
  String get chooseASupportedCondition;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose or enter a value.'**
  String get chooseOrEnterAValue;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The filter value is too long.'**
  String get theFilterValueIsTooLong;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose an available value.'**
  String get chooseAnAvailableValue;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Sign in to search your memberships.'**
  String get signInToSearchYourMemberships;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter file extensions separated by commas.'**
  String get enterFileExtensionsSeparatedByCommas;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid whole number.'**
  String get enterAValidWholeNumber;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose a valid date.'**
  String get chooseAValidDate;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter one username, group, or channel slug.'**
  String get enterOneUsernameGroupOrChannelSlug;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose one value for this condition.'**
  String get chooseOneValueForThisCondition;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter one language code, any, or none.'**
  String get enterOneLanguageCodeAnyOrNone;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose valid category slugs or tag names.'**
  String get chooseValidCategorySlugsOrTagNames;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove quotes from the value.'**
  String get removeQuotesFromTheValue;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This ordering is unavailable.'**
  String get thisOrderingIsUnavailable;

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unknown or unavailable search operator: {token}'**
  String unknownOrUnavailableSearchOperator(String token);

  /// English UI message used by shell/composer_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get table;

  /// English UI message used by shell/composer_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'| Column 1 | Column 2 |\n| --- | --- |\n|  |  |\n|  |  |'**
  String get column1Column2;

  /// English UI message used by shell/composer_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Column {column} heading'**
  String columnHeading(String column);

  /// English UI message used by shell/composer_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Row {row}, column {column}'**
  String rowColumn(String row, String column);

  /// English UI message used by shell/composer_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Heading'**
  String get heading;

  /// English UI message used by shell/composer_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Cell'**
  String get cell;

  /// English UI message used by shell/composer_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Column {column} actions'**
  String columnActions(String column);

  /// English UI message used by shell/composer_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Insert column before'**
  String get insertColumnBefore;

  /// English UI message used by shell/composer_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Insert column after'**
  String get insertColumnAfter;

  /// English UI message used by shell/composer_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Move column earlier'**
  String get moveColumnEarlier;

  /// English UI message used by shell/composer_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Move column later'**
  String get moveColumnLater;

  /// English UI message used by shell/composer_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Delete column'**
  String get deleteColumn;

  /// English UI message used by shell/composer_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Row {row} actions'**
  String rowActions(String row);

  /// English UI message used by shell/composer_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Insert row above'**
  String get insertRowAbove;

  /// English UI message used by shell/composer_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Insert row below'**
  String get insertRowBelow;

  /// English UI message used by shell/composer_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Move row up'**
  String get moveRowUp;

  /// English UI message used by shell/composer_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Move row down'**
  String get moveRowDown;

  /// English UI message used by shell/composer_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Delete row'**
  String get deleteRow;

  /// English UI message used by shell/composer_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Table editor'**
  String get tableEditor;

  /// English UI message used by shell/composer_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Editable table'**
  String get editableTable;

  /// English UI message used by shell/composer_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add a row to start writing.'**
  String get addARowToStartWriting;

  /// English UI message used by shell/composer_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Rows'**
  String get rows;

  /// English UI message used by shell/composer_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Column {column}'**
  String column(String column);

  /// English UI message used by shell/composer_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add row'**
  String get addRow;

  /// English UI message used by shell/composer_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add column'**
  String get addColumn;

  /// English UI message used by shell/composer_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove table'**
  String get removeTable;

  /// English UI message used by shell/panel_rail.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Restore panel'**
  String get restorePanel;

  /// English UI message used by shell/panel_rail.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Close a tab before opening another'**
  String get closeATabBeforeOpeningAnother;

  /// English UI message used by shell/panel_rail.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'New tab'**
  String get newTab;

  /// English UI message used by shell/topic_taxonomy_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dismiss {title} picker'**
  String dismissPicker(String title);

  /// English UI message used by shell/cooked_spoiler.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Spoiler'**
  String get spoilerCookedspoiler;

  /// English UI message used by shell/user_menu_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not open the sign-up page.'**
  String get couldNotOpenTheSignUpPage;

  /// English UI message used by shell/user_menu_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{unreadCount, plural, =1{Notifications, {unreadCount} unread item} other{Notifications, {unreadCount} unread items}}'**
  String notificationsUnread(num unreadCount);

  /// English UI message used by shell/user_menu_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{displayNameAccountUsername}, Profile'**
  String profileUsermenubutton(String displayNameAccountUsername);

  /// English UI message used by shell/user_menu_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get connecting;

  /// English UI message used by shell/user_menu_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Sign up'**
  String get signUp;

  /// English UI message used by shell/user_menu_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// English UI message used by shell/user_menu_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Signing in…'**
  String get signingIn;

  /// English UI message used by shell/discover_site_suggestions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Suggested communities'**
  String get suggestedCommunities;

  /// English UI message used by shell/discover_site_suggestions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Suggestions are unavailable right now.'**
  String get suggestionsAreUnavailableRightNow;

  /// English UI message used by shell/discover_site_suggestions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading suggested communities'**
  String get loadingSuggestedCommunities;

  /// English UI message used by shell/discover_site_suggestions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Discover more communities'**
  String get discoverMoreCommunities;

  /// English UI message used by shell/topic_filter_input.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Filter topics by category, tag, or other criteria'**
  String get filterTopicsByCategoryTagOrOtherCriteria;

  /// English UI message used by shell/topic_filter_input.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic filter query'**
  String get topicFilterQuery;

  /// English UI message used by shell/topic_filter_input.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Clear all filters'**
  String get clearAllFilters;

  /// English UI message used by shell/topic_filter_input.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Filter suggestions'**
  String get filterSuggestions;

  /// Accessible label for reopening a topic filter token to choose a new value.
  ///
  /// In en, this message translates to:
  /// **'Edit filter {label}'**
  String editTopicFilterToken(String label);

  /// English UI message used by shell/topic_filter_input.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove {label}'**
  String removeTopicfilterinput(String label);

  /// English UI message used by shell/post_text_selection.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Quote copied to clipboard.'**
  String get quoteCopiedToClipboard;

  /// English UI message used by shell/post_text_selection.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Copy quote'**
  String get copyQuote;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get checkAgain;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Create topic'**
  String get createTopic;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Whisper'**
  String get whisper;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Save and close'**
  String get saveAndClose;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Give your topic a title'**
  String get giveYourTopicATitle;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading that post…'**
  String get loadingThatPost;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Write your message…'**
  String get writeYourMessage;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Write your topic…'**
  String get writeYourTopic;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit this post…'**
  String get editThisPostComposerpanel;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reply to @{targetReplyToUsername}…'**
  String replyTo(String targetReplyToUsername);

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Write a reply…'**
  String get writeAReply;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t save this draft on this device.'**
  String get couldnTSaveThisDraftOnThisDevice;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Not saved on the site — kept on this device only.'**
  String get notSavedOnTheSiteKeptOnThisDeviceOnly;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Scroll to bottom'**
  String get scrollToBottom;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No subcategory'**
  String get noSubcategory;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get bold;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get italic;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Inline code'**
  String get inlineCode;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Formatting'**
  String get formatting;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Heading {level}'**
  String headingComposerpanel(String level);

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Numbered list'**
  String get numberedList;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Bulleted list'**
  String get bulletedList;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'To-do list'**
  String get toDoList;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get upload;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Composer editor'**
  String get composerEditor;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Image controls'**
  String get imageControls;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Decrease image size'**
  String get decreaseImageSize;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Increase image size'**
  String get increaseImageSize;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Delete image'**
  String get deleteImage;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Image description'**
  String get imageDescription;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add image description'**
  String get addImageDescription;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Save alt text'**
  String get saveAltText;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Gallery mode'**
  String get galleryMode;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Grid gallery mode'**
  String get gridGalleryMode;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Carousel gallery mode'**
  String get carouselGalleryMode;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add images to gallery'**
  String get addImagesToGallery;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Upload new images'**
  String get uploadNewImages;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add existing draft images'**
  String get addExistingDraftImages;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove gallery, keep images'**
  String get removeGalleryKeepImages;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add existing images'**
  String get addExistingImages;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Image {index}'**
  String imageComposerpanel(String index);

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add selected'**
  String get addSelected;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Insert'**
  String get insert;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Composer options'**
  String get composerOptions;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Show more composer tools'**
  String get showMoreComposerTools;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Show previous composer tools'**
  String get showPreviousComposerTools;

  /// English UI message used by shell/composer_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// English UI message used by shell/inline_video.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t download video. Try again.'**
  String get couldnTDownloadVideoTryAgain;

  /// English UI message used by shell/inline_video.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Downloading video…'**
  String get downloadingVideo;

  /// English UI message used by shell/inline_video.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Download video'**
  String get downloadVideo;

  /// English UI message used by shell/inline_video.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Play video: {dataTitle}'**
  String playVideo(String dataTitle);

  /// English UI message used by shell/inline_video.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Play video'**
  String get playVideoInlinevideo;

  /// English UI message used by shell/inline_video.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Video player: {dataTitle}'**
  String videoPlayer(String dataTitle);

  /// English UI message used by shell/inline_video.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Full-screen video player: {dataTitle}'**
  String fullScreenVideoPlayer(String dataTitle);

  /// English UI message used by shell/inline_video.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// English UI message used by shell/inline_video.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// English UI message used by shell/inline_video.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Exit full screen'**
  String get exitFullScreen;

  /// English UI message used by shell/inline_video.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter full screen'**
  String get enterFullScreen;

  /// English UI message used by shell/inline_video.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Playback position'**
  String get playbackPosition;

  /// English UI message used by shell/inline_video.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open video: {dataTitle}'**
  String openVideo(String dataTitle);

  /// English UI message used by shell/inline_video.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open video'**
  String get openVideoInlinevideo;

  /// English UI message used by shell/inline_video.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t play this video.'**
  String get couldnTPlayThisVideo;

  /// English UI message used by shell/inline_video.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get video;

  /// English UI message used by shell/categories_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No categories yet'**
  String get noCategoriesYet;

  /// English UI message used by shell/message_inbox_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Message lists'**
  String get messageLists;

  /// English UI message used by shell/post_checklist_write.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The post changed. Review its to-dos and try again.'**
  String get thePostChangedReviewItsToDosAndTryAgain;

  /// English UI message used by shell/post_checklist_write.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The post changed. Review its to-dos before continuing.'**
  String get thePostChangedReviewItsToDosBeforeContinuing;

  /// English UI message used by shell/post_checklist_write.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t confirm the to-do update. Refresh the post to check its saved state.'**
  String get couldnTConfirmTheToDoUpdateRefreshThePostTo;

  /// English UI message used by shell/post_footer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You flagged this post'**
  String get youFlaggedThisPost;

  /// English UI message used by shell/post_footer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You flagged this as off-topic'**
  String get youFlaggedThisAsOffTopic;

  /// English UI message used by shell/post_footer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You flagged this as spam'**
  String get youFlaggedThisAsSpam;

  /// English UI message used by shell/post_footer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You flagged this as inappropriate'**
  String get youFlaggedThisAsInappropriate;

  /// English UI message used by shell/post_footer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You flagged this as illegal'**
  String get youFlaggedThisAsIllegal;

  /// English UI message used by shell/post_footer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You flagged this for moderation'**
  String get youFlaggedThisForModeration;

  /// English UI message used by shell/post_footer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You sent a message to this user'**
  String get youSentAMessageToThisUser;

  /// English UI message used by shell/post_footer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You flagged this as {typeName}.'**
  String youFlaggedThisAs(String typeName);

  /// English UI message used by shell/mobile_shell.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Start page'**
  String get startPage;

  /// English UI message used by shell/mobile_shell.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Close navigation'**
  String get closeNavigation;

  /// English UI message used by shell/mobile_shell.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open navigation'**
  String get openNavigation;

  /// English UI message used by shell/mobile_shell.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get bookmarks;

  /// English UI message used by shell/mobile_shell.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reply to this topic'**
  String get replyToThisTopic;

  /// English UI message used by shell/mobile_shell.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'More destinations'**
  String get moreDestinations;

  /// English UI message used by shell/composer_recipients.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get selectedComposerrecipients;

  /// English UI message used by shell/composer_recipients.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Recipients'**
  String get recipients;

  /// English UI message used by shell/composer_recipients.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose recipients'**
  String get chooseRecipients;

  /// English UI message used by shell/composer_recipients.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Recipients: {recipientsJoin}'**
  String recipientsComposerrecipients(String recipientsJoin);

  /// English UI message used by shell/composer_recipients.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add users or groups'**
  String get addUsersOrGroups;

  /// English UI message used by shell/composer_recipients.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search recipients'**
  String get searchRecipients;

  /// English UI message used by shell/composer_recipients.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No users or groups found.'**
  String get noUsersOrGroupsFound;

  /// English UI message used by shell/composer_recipients.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get to;

  /// English UI message used by shell/open_link.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Close a tab before opening another.'**
  String get closeATabBeforeOpeningAnotherOpenlink;

  /// English UI message used by shell/open_link.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open link'**
  String get openLinkOpenlink;

  /// English UI message used by shell/open_link.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open in main panel'**
  String get openInMainPanel;

  /// English UI message used by shell/open_link.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open in secondary panel'**
  String get openInSecondaryPanel;

  /// English UI message used by shell/open_link.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open in new main tab'**
  String get openInNewMainTab;

  /// English UI message used by shell/open_link.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open in new secondary tab'**
  String get openInNewSecondaryTab;

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Connect this account to see its summary'**
  String get connectThisAccountToSeeItsSummary;

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Highlights'**
  String get highlights;

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Connections'**
  String get connections;

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get reading;

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Time reading'**
  String get timeReading;

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'read time: {timeLong}, all time'**
  String readTimeAllTime(String timeLong);

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Your story starts with a conversation.'**
  String get yourStoryStartsWithAConversation;

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'As you read, reply and connect with people, your highlights will appear here.'**
  String get asYouReadReplyAndConnectWithPeopleYourHighlightsWill;

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Top topics'**
  String get topTopics;

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No topics yet.'**
  String get noTopicsYet;

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Top replies'**
  String get topReplies;

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Your milestones'**
  String get yourMilestones;

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No connections yet.'**
  String get noConnectionsYet;

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The people you reply to and exchange likes with will appear here.'**
  String get thePeopleYouReplyToAndExchangeLikesWithWillAppear;

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Most replied to'**
  String get mostRepliedTo;

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Most liked by'**
  String get mostLikedBy;

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No likes yet.'**
  String get noLikesYet;

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Time well spent'**
  String get timeWellSpent;

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{recentShort} in the last 60 days'**
  String inTheLast60Days(String recentShort);

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'recent read time: {recentLong}, in the last 60 days'**
  String recentReadTimeInTheLast60Days(String recentLong);

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'All-time reading'**
  String get allTimeReading;

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Top categories'**
  String get topCategories;

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Top links'**
  String get topLinks;

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Replies written'**
  String get repliesWritten;

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topics started'**
  String get topicsStarted;

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open {topicTitle}'**
  String openUsersummary(String topicTitle);

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No links yet.'**
  String get noLinksYet;

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open external link {shortUrlLinkUrl}, {linkClicksClick}'**
  String openExternalLink(String shortUrlLinkUrl, String linkClicksClick);

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open {linkTopicTitle}'**
  String openUsersummaryValue(String linkTopicTitle);

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'View profile for {userDisplayName}, {nounPluralPluralNoun}'**
  String viewProfileForUsersummary(
    String userDisplayName,
    String nounPluralPluralNoun,
  );

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{topics, select, true{Search {categoryTopicCountTopic} by @{username} in {categoryName}} other{Search {replyPluralReplies} by @{username} in {categoryName}}}'**
  String searchByIn(
    String topics,
    String categoryTopicCountTopic,
    String username,
    String categoryName,
    String replyPluralReplies,
  );

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No badges yet.'**
  String get noBadgesYet;

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading summary'**
  String get loadingSummary;

  /// English UI message used by shell/topic_tag_selector.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get tagTopictagselector;

  /// English UI message used by shell/topic_tag_selector.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'All tags'**
  String get allTags;

  /// English UI message used by shell/topic_tag_selector.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Tags: {tagNameJoin}'**
  String tagsTopictagselector(String tagNameJoin);

  /// English UI message used by shell/topic_tag_selector.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search tags…'**
  String get searchTags;

  /// English UI message used by shell/topic_tag_selector.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search tags'**
  String get searchTagsTopictagselector;

  /// English UI message used by shell/topic_tag_selector.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No tags are available.'**
  String get noTagsAreAvailable;

  /// English UI message used by shell/forum_theme_new_dialog.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'My theme'**
  String get myTheme;

  /// English UI message used by shell/forum_theme_new_dialog.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'New theme'**
  String get newTheme;

  /// English UI message used by shell/forum_theme_new_dialog.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Start from'**
  String get startFrom;

  /// English UI message used by shell/forum_theme_new_dialog.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get messageContinue;

  /// English UI message used by shell/preferences_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to {instanceHost} to load preferences.'**
  String reconnectToToLoadPreferences(String instanceHost);

  /// English UI message used by shell/preferences_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This account is not allowed to edit these preferences.'**
  String get thisAccountIsNotAllowedToEditThesePreferences;

  /// English UI message used by shell/preferences_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load preferences from {instanceHost}.'**
  String couldnTLoadPreferencesFrom(String instanceHost);

  /// English UI message used by shell/preferences_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to {host} to update preferences.'**
  String reconnectToToUpdatePreferences(String host);

  /// English UI message used by shell/preferences_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'These preferences changed elsewhere. Reload and try again.'**
  String get thesePreferencesChangedElsewhereReloadAndTryAgain;

  /// English UI message used by shell/preferences_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t update preferences on {host}.'**
  String couldnTUpdatePreferencesOn(String host);

  /// English UI message used by shell/adaptive_dialog_action.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Confirmation'**
  String get confirmation;

  /// English UI message used by shell/category_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Every new post and unread count'**
  String get everyNewPostAndUnreadCount;

  /// English UI message used by shell/category_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Mentions, replies, and unread count'**
  String get mentionsRepliesAndUnreadCount;

  /// English UI message used by shell/category_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Watching First Post'**
  String get watchingFirstPost;

  /// English UI message used by shell/category_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'New topics only'**
  String get newTopicsOnly;

  /// English UI message used by shell/category_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Mentions and replies only'**
  String get mentionsAndRepliesOnly;

  /// English UI message used by shell/category_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Muted'**
  String get muted;

  /// English UI message used by shell/category_notifications.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No notifications; hidden from Latest'**
  String get noNotificationsHiddenFromLatest;

  /// English UI message used by shell/composer_draft_coordinator.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t check for an existing draft. Try again.'**
  String get couldnTCheckForAnExistingDraftTryAgain;

  /// English UI message used by shell/composer_draft_coordinator.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t discard this draft. Try again.'**
  String get couldnTDiscardThisDraftTryAgain;

  /// English UI message used by shell/composer_draft_coordinator.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This draft changed before it could be discarded. Review it and try again.'**
  String get thisDraftChangedBeforeItCouldBeDiscardedReviewItAnd;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to this forum to load preferences.'**
  String get reconnectToThisForumToLoadPreferences;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get preferences;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Saving preferences'**
  String get savingPreferences;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Save preferences'**
  String get savePreferences;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Saving changes…'**
  String get savingChanges;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Like notifications'**
  String get likeNotifications;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose when likes should create a notification.'**
  String get chooseWhenLikesShouldCreateANotification;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'First time and daily'**
  String get firstTimeAndDaily;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'First time'**
  String get firstTime;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Notify me about replies to linked posts'**
  String get notifyMeAboutRepliesToLinkedPosts;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Get a notification when someone replies to a post you linked.'**
  String get getANotificationWhenSomeoneRepliesToAPostYouLinked;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Consider topics new'**
  String get considerTopicsNew;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Controls which topics appear as new to this account.'**
  String get controlsWhichTopicsAppearAsNewToThisAccount;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Until I view them'**
  String get untilIViewThem;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'For one day'**
  String get forOneDay;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'For two days'**
  String get forTwoDays;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'For one week'**
  String get forOneWeek;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'For two weeks'**
  String get forTwoWeeks;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Since my last visit'**
  String get sinceMyLastVisit;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Automatically track topics'**
  String get automaticallyTrackTopics;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Track a topic after you have read it for this long.'**
  String get trackATopicAfterYouHaveReadItForThisLong;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Immediately'**
  String get immediately;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'After 30 seconds'**
  String get after30Seconds;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'After 1 minute'**
  String get after1Minute;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'After 2 minutes'**
  String get after2Minutes;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'After 3 minutes'**
  String get after3Minutes;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'After 4 minutes'**
  String get after4Minutes;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'After 5 minutes'**
  String get after5Minutes;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'After 10 minutes'**
  String get after10Minutes;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'When I reply to a topic'**
  String get whenIReplyToATopic;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose the notification level applied after a reply.'**
  String get chooseTheNotificationLevelAppliedAfterAReply;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Watch the topic'**
  String get watchTheTopic;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Track the topic'**
  String get trackTheTopic;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Keep the current level'**
  String get keepTheCurrentLevel;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Type to filter IANA timezones used for dates and reminders.'**
  String get typeToFilterIANATimezonesUsedForDatesAndReminders;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Device timezone is unavailable.'**
  String get deviceTimezoneIsUnavailable;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Device timezone: {deviceTimezone}'**
  String deviceTimezone(String deviceTimezone);

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Use device timezone'**
  String get useDeviceTimezone;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Automatically delete bookmarks'**
  String get automaticallyDeleteBookmarks;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose what happens after a bookmark reminder.'**
  String get chooseWhatHappensAfterABookmarkReminder;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'After the reminder is sent'**
  String get afterTheReminderIsSent;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'When the topic owner replies'**
  String get whenTheTopicOwnerReplies;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'When the reminder is cleared'**
  String get whenTheReminderIsCleared;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{sectionTitleSectionPluginSections} preferences saved.'**
  String preferencesSaved(String sectionTitleSectionPluginSections);

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Refreshing preferences…'**
  String get refreshingPreferences;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading preferences from {host}.'**
  String loadingPreferencesFrom(String host);

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading preferences…'**
  String get loadingPreferences;

  /// English UI message used by shell/preferences_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Interface'**
  String get interface;

  /// English UI message used by shell/topic_create_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic creation actions'**
  String get topicCreationActions;

  /// English UI message used by shell/topic_create_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open the latest drafts menu'**
  String get openTheLatestDraftsMenu;

  /// English UI message used by shell/topic_create_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Recent drafts'**
  String get recentDrafts;

  /// English UI message used by shell/topic_create_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'All drafts'**
  String get allDrafts;

  /// English UI message used by shell/topic_create_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading drafts…'**
  String get loadingDraftsTopiccreatebutton;

  /// English UI message used by shell/topic_create_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load drafts.'**
  String get couldnTLoadDrafts;

  /// English UI message used by shell/topic_create_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'View all drafts, {otherDraftCount} other {noun}'**
  String viewAllDraftsOther(String otherDraftCount, String noun);

  /// English UI message used by shell/topic_create_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'view all drafts'**
  String get viewAllDrafts;

  /// English UI message used by shell/composer_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit category'**
  String get editCategory;

  /// English UI message used by shell/composer_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit topic'**
  String get editTopic;

  /// English UI message used by shell/composer_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit post #{targetEditingPostNumber}'**
  String editPost(String targetEditingPostNumber);

  /// English UI message used by shell/composer_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Resume editing: {label}'**
  String resumeEditing(String label);

  /// English UI message used by shell/composer_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Restore composer'**
  String get restoreComposer;

  /// English UI message used by shell/composer_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Resume editing'**
  String get resumeEditingComposerheader;

  /// English UI message used by shell/composer_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reply visibility'**
  String get replyVisibility;

  /// English UI message used by shell/composer_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Whisper, Allowed groups only'**
  String get whisperAllowedGroupsOnly;

  /// English UI message used by shell/composer_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Allowed groups only'**
  String get allowedGroupsOnly;

  /// English UI message used by shell/composer_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Whisper options'**
  String get whisperOptions;

  /// English UI message used by shell/composer_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reply options'**
  String get replyOptions;

  /// English UI message used by shell/composer_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Composer actions'**
  String get composerActions;

  /// English UI message used by shell/composer_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get minimize;

  /// English UI message used by shell/composer_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Save draft'**
  String get saveDraft;

  /// English UI message used by shell/composer_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Return to {targetTopicTitle}'**
  String returnTo(String targetTopicTitle);

  /// English UI message used by shell/composer_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dock side'**
  String get dockSide;

  /// English UI message used by shell/composer_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Composer view'**
  String get composerView;

  /// English UI message used by shell/composer_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Full screen'**
  String get fullScreen;

  /// English UI message used by shell/composer_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Minimize composer'**
  String get minimizeComposer;

  /// English UI message used by shell/composer_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Not saved'**
  String get notSaved;

  /// English UI message used by shell/composer_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Device only'**
  String get deviceOnly;

  /// English UI message used by shell/forum_tabs_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open tabs in {forumName}'**
  String openTabsIn(String forumName);

  /// English UI message used by shell/forum_tabs_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Move to secondary panel'**
  String get moveToSecondaryPanel;

  /// English UI message used by shell/forum_tabs_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Move to main panel'**
  String get moveToMainPanel;

  /// English UI message used by shell/forum_tabs_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Browse tabs'**
  String get browseTabs;

  /// English UI message used by shell/forum_tabs_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search tabs...'**
  String get searchTabs;

  /// English UI message used by shell/forum_tabs_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Close {itemTitle}'**
  String closeForumtabsbar(String itemTitle);

  /// English UI message used by shell/forum_tabs_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Browse tabs in {forumName}'**
  String browseTabsIn(String forumName);

  /// English UI message used by shell/forum_tabs_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Lists'**
  String get lists;

  /// English UI message used by shell/forum_tabs_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Recently closed '**
  String get recentlyClosed;

  /// English UI message used by shell/forum_tabs_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Drop {itemTitle} here'**
  String dropHere(String itemTitle);

  /// English UI message used by shell/forum_tabs_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open a new tab'**
  String get openANewTab;

  /// English UI message used by shell/forum_tabs_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Show more tabs'**
  String get showMoreTabs;

  /// English UI message used by shell/forum_tabs_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Show previous tabs'**
  String get showPreviousTabs;

  /// English UI message used by shell/forum_tabs_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// English UI message used by shell/forum_tabs_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'urgent unread activity'**
  String get urgentUnreadActivity;

  /// English UI message used by shell/forum_tabs_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'unread activity'**
  String get unreadActivity;

  /// English UI message used by shell/forum_tabs_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'unread item'**
  String get unreadItem;

  /// English UI message used by shell/forum_tabs_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'unread items'**
  String get unreadItems;

  /// English UI message used by shell/forum_tabs_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Move left'**
  String get moveLeft;

  /// English UI message used by shell/forum_tabs_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Move right'**
  String get moveRight;

  /// English UI message used by shell/forum_tabs_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Show tab actions'**
  String get showTabActions;

  /// English UI message used by shell/forum_tabs_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Tab actions'**
  String get tabActions;

  /// English UI message used by shell/forum_tabs_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Close tab'**
  String get closeTab;

  /// English UI message used by shell/forum_tabs_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Close other tabs'**
  String get closeOtherTabs;

  /// English UI message used by shell/composer_media_editing_coordinator.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t open the image picker.'**
  String get couldnTOpenTheImagePicker;

  /// English UI message used by shell/topic_list_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Filter topics'**
  String get filterTopics;

  /// English UI message used by shell/topic_list_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add a filter…'**
  String get addAFilter;

  /// English UI message used by shell/topic_list_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open topics'**
  String get openTopics;

  /// English UI message used by shell/topic_list_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unanswered'**
  String get unanswered;

  /// English UI message used by shell/topic_list_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Closed topics'**
  String get closedTopics;

  /// English UI message used by shell/topic_list_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unread replies'**
  String get unreadReplies;

  /// English UI message used by shell/topic_list_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'New topics'**
  String get newTopicsTopiclistactions;

  /// English UI message used by shell/topic_list_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Apply filter'**
  String get applyFilter;

  /// English UI message used by shell/topic_list_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit active filter'**
  String get editActiveFilter;

  /// English UI message used by shell/forum_appearance_effects.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Texture'**
  String get texture;

  /// English UI message used by shell/forum_appearance_effects.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Paper'**
  String get paper;

  /// English UI message used by shell/forum_appearance_effects.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Lava lamp'**
  String get lavaLamp;

  /// English UI message used by shell/forum_appearance_effects.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Gradient'**
  String get gradient;

  /// English UI message used by shell/forum_appearance_effects.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Intensity'**
  String get intensity;

  /// English UI message used by shell/forum_appearance_effects.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Opacity'**
  String get opacity;

  /// English UI message used by shell/forum_appearance_effects.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Tint'**
  String get tint;

  /// English UI message used by shell/user_summary_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to {instanceHost} to see your summary.'**
  String reconnectToToSeeYourSummary(String instanceHost);

  /// English UI message used by shell/user_summary_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load your summary from {instanceHost}.'**
  String couldnTLoadYourSummaryFrom(String instanceHost);

  /// English UI message used by shell/composer_reply_context.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Replying to this topic'**
  String get replyingToThisTopic;

  /// English UI message used by shell/composer_reply_context.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Replying to @{username}'**
  String replyingToComposerreplycontext(String username);

  /// English UI message used by shell/composer_reply_context.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Replying to '**
  String get replyingToComposerreplycontextValue;

  /// English UI message used by shell/emoji_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dismiss emoji picker'**
  String get dismissEmojiPicker;

  /// English UI message used by shell/emoji_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No emoji are available.'**
  String get noEmojiAreAvailable;

  /// English UI message used by shell/emoji_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No emoji found.'**
  String get noEmojiFound;

  /// English UI message used by shell/emoji_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Frequently used'**
  String get frequentlyUsed;

  /// English UI message used by shell/emoji_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search emoji'**
  String get searchEmoji;

  /// English UI message used by shell/emoji_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Skin tone: {toneLabelControllerTone}'**
  String skinTone(String toneLabelControllerTone);

  /// English UI message used by shell/emoji_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose skin tone'**
  String get chooseSkinTone;

  /// English UI message used by shell/emoji_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Clear frequently used emoji'**
  String get clearFrequentlyUsedEmoji;

  /// English UI message used by shell/emoji_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Insert :{choiceCode}:'**
  String insertEmojipicker(String choiceCode);

  /// English UI message used by shell/emoji_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Smileys & emotion'**
  String get smileysEmotion;

  /// English UI message used by shell/emoji_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'People & body'**
  String get peopleBody;

  /// English UI message used by shell/emoji_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Animals & nature'**
  String get animalsNature;

  /// English UI message used by shell/emoji_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Food & drink'**
  String get foodDrink;

  /// English UI message used by shell/emoji_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Travel & places'**
  String get travelPlaces;

  /// English UI message used by shell/emoji_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Activities'**
  String get activities;

  /// English UI message used by shell/emoji_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Objects'**
  String get objects;

  /// English UI message used by shell/emoji_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Symbols'**
  String get symbols;

  /// English UI message used by shell/emoji_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Flags'**
  String get flags;

  /// English UI message used by shell/emoji_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Custom emojis'**
  String get customEmojis;

  /// English UI message used by shell/emoji_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Neutral'**
  String get neutral;

  /// English UI message used by shell/emoji_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// English UI message used by shell/emoji_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Medium-light'**
  String get mediumLight;

  /// English UI message used by shell/emoji_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get medium;

  /// English UI message used by shell/emoji_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Medium-dark'**
  String get mediumDark;

  /// English UI message used by shell/emoji_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// English UI message used by shell/composer_slash_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Composer commands'**
  String get composerCommands;

  /// English UI message used by shell/composer_slash_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No matching commands.'**
  String get noMatchingCommands;

  /// English UI message used by shell/composer_slash_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Close menu'**
  String get closeMenu;

  /// English UI message used by shell/composer_slash_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Type to search'**
  String get typeToSearch;

  /// English UI message used by shell/forum_theme_clipboard.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Theme copied. Paste it into a post or chat.'**
  String get themeCopiedPasteItIntoAPostOrChat;

  /// English UI message used by shell/forum_theme_clipboard.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not copy theme. Try again.'**
  String get couldNotCopyThemeTryAgain;

  /// English UI message used by shell/global_search_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Use at most 30 conditions.'**
  String get useAtMost30Conditions;

  /// English UI message used by shell/global_search_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Recent searches could not be cleared. Please try again.'**
  String get recentSearchesCouldNotBeClearedPleaseTryAgain;

  /// English UI message used by shell/global_search_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Searches can be at most 2048 characters.'**
  String get searchesCanBeAtMost2048Characters;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Bookmark post'**
  String get bookmarkPost;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Post bookmark'**
  String get postBookmark;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic bookmark'**
  String get topicBookmark;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic bookmarks'**
  String get topicBookmarks;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Delete bookmark?'**
  String get deleteBookmark;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This also removes its scheduled reminder.'**
  String get thisAlsoRemovesItsScheduledReminder;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Delete all bookmarks?'**
  String get deleteAllBookmarks;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Every topic and post bookmark in this topic will be removed.'**
  String get everyTopicAndPostBookmarkInThisTopicWillBeRemoved;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Delete all'**
  String get deleteAll;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Saving bookmark'**
  String get savingBookmark;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Saving bookmark…'**
  String get savingBookmarkBookmarkui;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The bookmark was not saved.'**
  String get theBookmarkWasNotSaved;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Bookmarked!'**
  String get bookmarkedBookmarkui;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Clear reminder'**
  String get clearReminder;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Delete bookmark'**
  String get deleteBookmarkBookmarkui;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'That local time does not exist because of daylight saving time.'**
  String get thatLocalTimeDoesNotExistBecauseOfDaylightSavingTime;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter a positive reminder duration.'**
  String get enterAPositiveReminderDuration;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose a reminder in the future.'**
  String get chooseAReminderInTheFuture;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose a reminder no more than 10 years away.'**
  String get chooseAReminderNoMoreThan10YearsAway;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get noteBookmarkui;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Why are you saving this?'**
  String get whyAreYouSavingThis;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Afterward'**
  String get afterward;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remind me'**
  String get remindMe;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Times use {zoneName}.'**
  String timesUse(String zoneName);

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Date in post'**
  String get dateInPost;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Last custom time'**
  String get lastCustomTime;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Custom date and time'**
  String get customDateAndTime;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No reminder'**
  String get noReminder;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'In'**
  String get messageIn;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get messageSet;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reminder: {contextReminderZoneName}'**
  String reminder(String contextReminderZoneName);

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This topic is no longer available.'**
  String get thisTopicIsNoLongerAvailable;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Post #{bookmarkPostNumber}'**
  String postBookmarkui(String bookmarkPostNumber);

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Post bookmark actions'**
  String get postBookmarkActions;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Jump'**
  String get jump;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Delete all bookmarks'**
  String get deleteAllBookmarksBookmarkui;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Keep bookmark'**
  String get keepBookmark;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Delete after the reminder'**
  String get deleteAfterTheReminder;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Delete once I reply'**
  String get deleteOnceIReply;

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Keep bookmark and clear reminder'**
  String get keepBookmarkAndClearReminder;

  /// English UI message used by shell/composer_image_gallery.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{itemsLength, plural, =1{Image gallery, {itemsLength} image} other{Image gallery, {itemsLength} images}}'**
  String imageGalleryComposerimagegallery(num itemsLength);

  /// English UI message used by shell/composer_image_gallery.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{count}. Add or remove images.'**
  String addOrRemoveImages(String count);

  /// English UI message used by shell/composer_image_gallery.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Gallery options'**
  String get galleryOptions;

  /// English UI message used by shell/composer_tag_removal_notice.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Some tags were removed'**
  String get someTagsWereRemoved;

  /// English UI message used by shell/composer_tag_removal_notice.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dismiss tag notice'**
  String get dismissTagNotice;

  /// English UI message used by shell/code_block.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Bash'**
  String get bash;

  /// English UI message used by shell/code_block.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Clojure'**
  String get clojure;

  /// English UI message used by shell/code_block.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dart'**
  String get dart;

  /// English UI message used by shell/code_block.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Diff'**
  String get diff;

  /// English UI message used by shell/code_block.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dockerfile'**
  String get dockerfile;

  /// English UI message used by shell/code_block.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Elixir'**
  String get elixir;

  /// English UI message used by shell/code_block.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Go'**
  String get go;

  /// English UI message used by shell/code_block.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Handlebars'**
  String get handlebars;

  /// English UI message used by shell/code_block.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Java'**
  String get java;

  /// English UI message used by shell/code_block.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Kotlin'**
  String get kotlin;

  /// English UI message used by shell/code_block.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Markdown'**
  String get markdown;

  /// English UI message used by shell/code_block.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Objective-C'**
  String get objectiveC;

  /// English UI message used by shell/code_block.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Plain text'**
  String get plainText;

  /// English UI message used by shell/code_block.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Python'**
  String get python;

  /// English UI message used by shell/code_block.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Ruby'**
  String get ruby;

  /// English UI message used by shell/code_block.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Rust'**
  String get rust;

  /// English UI message used by shell/code_block.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Shell'**
  String get shell;

  /// English UI message used by shell/code_block.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Swift'**
  String get swift;

  /// English UI message used by shell/code_block.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get code;

  /// English UI message used by shell/code_block.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'View code full screen'**
  String get viewCodeFullScreen;

  /// English UI message used by shell/code_block.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Close code viewer'**
  String get closeCodeViewer;

  /// English UI message used by shell/code_block.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Post code'**
  String get postCode;

  /// English UI message used by shell/code_block.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t copy code.'**
  String get couldnTCopyCode;

  /// English UI message used by shell/code_block.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get codeCopied;

  /// English UI message used by shell/instance_sidebar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'New Topic'**
  String get newTopicInstancesidebar;

  /// English UI message used by shell/instance_sidebar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts'**
  String get shortcutsInstancesidebar;

  /// English UI message used by shell/instance_sidebar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Forum'**
  String get forum;

  /// English UI message used by shell/instance_sidebar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open forum in browser'**
  String get openForumInBrowser;

  /// English UI message used by shell/instance_sidebar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{name}, forum menu'**
  String forumMenu(String name);

  /// English UI message used by shell/instance_sidebar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading navigation'**
  String get loadingNavigation;

  /// English UI message used by shell/instance_sidebar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Move public link?'**
  String get movePublicLink;

  /// English UI message used by shell/instance_sidebar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This changes a public sidebar section for everyone on this forum.'**
  String get thisChangesAPublicSidebarSectionForEveryoneOnThisForum;

  /// English UI message used by shell/instance_sidebar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t move link. Try again.'**
  String get couldnTMoveLinkTryAgain;

  /// English UI message used by shell/instance_sidebar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reorder public links?'**
  String get reorderPublicLinks;

  /// English UI message used by shell/instance_sidebar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This changes the sidebar link order for everyone on this forum.'**
  String get thisChangesTheSidebarLinkOrderForEveryoneOnThisForum;

  /// English UI message used by shell/instance_sidebar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reorder'**
  String get reorder;

  /// English UI message used by shell/instance_sidebar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t reorder links. Try again.'**
  String get couldnTReorderLinksTryAgain;

  /// English UI message used by shell/instance_sidebar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading {sectionTitle}'**
  String loadingInstancesidebar(String sectionTitle);

  /// English UI message used by shell/instance_sidebar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading {destinationLabel}'**
  String loadingInstancesidebarValue(String destinationLabel);

  /// English UI message used by shell/instance_sidebar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unread mentions'**
  String get unreadMentions;

  /// English UI message used by shell/instance_sidebar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open {destinationLabel}'**
  String openInstancesidebar(String destinationLabel);

  /// English UI message used by shell/post_permanent_delete.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'permanently delete'**
  String get permanentlyDeletePostpermanentdelete;

  /// English UI message used by shell/post_permanent_delete.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Cannot permanently delete'**
  String get cannotPermanentlyDelete;

  /// English UI message used by shell/post_permanent_delete.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete {target}?'**
  String permanentlyDeletePostpermanentdeleteValue(String target);

  /// English UI message used by shell/post_permanent_delete.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone. The {target} will be removed from the database.'**
  String thisCannotBeUndoneTheWillBeRemovedFromTheDatabase(String target);

  /// English UI message used by shell/post_permanent_delete.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Type “{confirmationPhrase}” to confirm.'**
  String typeToConfirm(String confirmationPhrase);

  /// English UI message used by shell/adaptive_shell.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Resize diagnostics panel'**
  String get resizeDiagnosticsPanel;

  /// English UI message used by shell/adaptive_shell.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Sign in to continue'**
  String get signInToContinue;

  /// English UI message used by shell/adaptive_shell.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{siteTitle} is a private forum. Sign in to view its topics and conversations.'**
  String isAPrivateForumSignInToViewItsTopicsAnd(String siteTitle);

  /// English UI message used by shell/adaptive_shell.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'\'t reach this community. Check its address or your internet connection, then try again.'**
  String get weCouldnTReachThisCommunityCheckItsAddressOrYour;

  /// English UI message used by shell/adaptive_shell.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Trying again…'**
  String get tryingAgain;

  /// English UI message used by shell/adaptive_shell.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Resize sidebar'**
  String get resizeSidebar;

  /// English UI message used by shell/adaptive_shell.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load your sites'**
  String get couldnTLoadYourSites;

  /// English UI message used by shell/adaptive_shell.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Your saved sites have not been changed. Try loading them again.'**
  String get yourSavedSitesHaveNotBeenChangedTryLoadingThemAgain;

  /// English UI message used by shell/topic_list_footer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose forum for new topic'**
  String get chooseForumForNewTopic;

  /// English UI message used by shell/topic_list_footer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Previous topic'**
  String get previousTopic;

  /// English UI message used by shell/topic_list_footer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Next topic'**
  String get nextTopic;

  /// English UI message used by shell/aggregate_feed_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t refresh {instanceHost}.'**
  String couldnTRefresh(String instanceHost);

  /// English UI message used by shell/aggregate_feed_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load more from {sourceInstanceHost}.'**
  String couldnTLoadMoreFrom(String sourceInstanceHost);

  /// English UI message used by shell/aggregate_branding.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Discourse'**
  String get discourse;

  /// English UI message used by shell/new_tab_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get due;

  /// English UI message used by shell/new_tab_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reminder'**
  String get reminderNewtabpage;

  /// English UI message used by shell/new_tab_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Comfortable'**
  String get comfortable;

  /// English UI message used by shell/new_tab_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Compact'**
  String get compact;

  /// English UI message used by shell/new_tab_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Recently closed'**
  String get recentlyClosedNewtabpage;

  /// English UI message used by shell/new_tab_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Everything else'**
  String get everythingElse;

  /// English UI message used by shell/new_tab_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Badges'**
  String get badges;

  /// English UI message used by shell/new_tab_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Browse latest topics'**
  String get browseLatestTopics;

  /// English UI message used by shell/new_tab_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Post #{number}'**
  String postNewtabpage(String number);

  /// English UI message used by shell/new_tab_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Work with two panels'**
  String get workWithTwoPanels;

  /// English UI message used by shell/new_tab_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Middle click'**
  String get middleClick;

  /// English UI message used by shell/new_tab_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Opens a new tab in main panel'**
  String get opensANewTabInMainPanel;

  /// English UI message used by shell/new_tab_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Click'**
  String get click;

  /// English UI message used by shell/new_tab_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open in a new tab in secondary panel'**
  String get openInANewTabInSecondaryPanel;

  /// English UI message used by shell/new_tab_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Don\'\'t show this tutorial again'**
  String get donTShowThisTutorialAgain;

  /// English UI message used by shell/new_tab_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Main'**
  String get main;

  /// English UI message used by shell/new_tab_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Secondary'**
  String get secondary;

  /// English UI message used by shell/new_tab_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Shift + click opens here'**
  String get shiftClickOpensHere;

  /// English UI message used by shell/draft_list_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to {instanceHost} to see your drafts.'**
  String reconnectToToSeeYourDrafts(String instanceHost);

  /// English UI message used by shell/draft_list_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load drafts from {instanceHost}.'**
  String couldnTLoadDraftsFrom(String instanceHost);

  /// English UI message used by shell/draft_list_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load more drafts from {instanceHost}.'**
  String couldnTLoadMoreDraftsFrom(String instanceHost);

  /// English UI message used by shell/draft_list_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t remove that draft. Try again.'**
  String get couldnTRemoveThatDraftTryAgain;

  /// English UI message used by shell/emoji_picker_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load emoji. Check the connection and try again.'**
  String get couldnTLoadEmojiCheckTheConnectionAndTryAgain;

  /// English UI message used by shell/image_download.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The image could not be downloaded.'**
  String get theImageCouldNotBeDownloaded;

  /// English UI message used by shell/message_archive_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'your inbox'**
  String get yourInbox;

  /// English UI message used by shell/message_archive_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'your inboxes'**
  String get yourInboxes;

  /// English UI message used by shell/message_archive_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Move to {scope}'**
  String moveTo(String scope);

  /// English UI message used by shell/message_archive_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Archive from {scope}'**
  String archiveFrom(String scope);

  /// English UI message used by shell/message_archive_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Move to inbox'**
  String get moveToInbox;

  /// English UI message used by shell/message_archive_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Archived from {scope}'**
  String archivedFrom(String scope);

  /// English UI message used by shell/message_archive_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Moved to {scope}'**
  String movedTo(String scope);

  /// English UI message used by shell/composer_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose at least {countLabelMinimumRequiredTagsTag} for this category.'**
  String chooseAtLeastForThisCategory(String countLabelMinimumRequiredTagsTag);

  /// English UI message used by shell/composer_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'They aren’t available in this category.'**
  String get theyArenTAvailableInThisCategory;

  /// English UI message used by shell/composer_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'They aren’t available in {categoryName}.'**
  String theyArenTAvailableIn(String categoryName);

  /// English UI message used by shell/composer_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'That gallery changed, so the images will be added outside it.'**
  String get thatGalleryChangedSoTheImagesWillBeAddedOutsideIt;

  /// English UI message used by shell/composer_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **' for images'**
  String get forImages;

  /// English UI message used by shell/composer_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'That file type is not allowed{purpose} on this site.'**
  String thatFileTypeIsNotAllowedOnThisSite(String purpose);

  /// English UI message used by shell/composer_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{rejected} file types are not allowed{purpose} on this site.'**
  String fileTypesAreNotAllowedOnThisSite(String rejected, String purpose);

  /// English UI message used by shell/composer_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Upload at most {limit} at a time.'**
  String uploadAtMostAtATime(String limit);

  /// English UI message used by shell/composer_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t upload {fileName}.'**
  String couldnTUpload(String fileName);

  /// English UI message used by shell/composer_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Checking whether that posted…'**
  String get checkingWhetherThatPosted;

  /// English UI message used by shell/composer_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'That may have posted — the site could not be reached to check. Check again before sending it a second time.'**
  String get thatMayHavePostedTheSiteCouldNotBeReachedTo;

  /// English UI message used by shell/composer_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Your reply was sent for review, so it is not posted yet.'**
  String get yourReplyWasSentForReviewSoItIsNotPosted;

  /// English UI message used by shell/topic_taxonomy_fields.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Parent category: {parentCategoryName}'**
  String parentCategoryTopictaxonomyfields(String parentCategoryName);

  /// English UI message used by shell/topic_taxonomy_fields.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open category {parentCategoryName}'**
  String openCategory(String parentCategoryName);

  /// English UI message used by shell/topic_taxonomy_fields.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open category {categoryName}'**
  String openCategoryTopictaxonomyfields(String categoryName);

  /// English UI message used by shell/topic_taxonomy_fields.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open category {label}'**
  String openCategoryTopictaxonomyfieldsValue(String label);

  /// English UI message used by shell/topic_taxonomy_fields.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Category: {label}'**
  String categoryTopictaxonomyfields(String label);

  /// English UI message used by shell/topic_taxonomy_fields.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Saving topic tags'**
  String get savingTopicTags;

  /// English UI message used by shell/topic_taxonomy_fields.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get saving;

  /// English UI message used by shell/category_icon.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Private category'**
  String get privateCategory;

  /// English UI message used by shell/composer_quote_component.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Quote from {title}'**
  String quoteFrom(String title);

  /// English UI message used by shell/post_likes.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'1 like'**
  String get message1Like;

  /// English UI message used by shell/post_likes.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{postLiked, select, true{1 like, from you} other{1 like, from someone else}}'**
  String message1LikeFrom(String postLiked);

  /// English UI message used by shell/post_likes.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'show who liked this post'**
  String get showWhoLikedThisPost;

  /// English UI message used by shell/post_likes.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'remove your like'**
  String get removeYourLikePostlikes;

  /// English UI message used by shell/post_likes.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'like this post'**
  String get likeThisPostPostlikes;

  /// English UI message used by shell/post_likes.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'and 1 other'**
  String get and1Other;

  /// English UI message used by shell/topic_category_selector.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load categories.'**
  String get couldnTLoadCategories;

  /// English UI message used by shell/topic_category_selector.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'All {noun}'**
  String allTopiccategoryselector(String noun);

  /// English UI message used by shell/topic_category_selector.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Filter by category'**
  String get filterByCategory;

  /// English UI message used by shell/topic_category_selector.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose category'**
  String get chooseCategory;

  /// English UI message used by shell/topic_category_selector.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Filter by subcategory of {parentName}'**
  String filterBySubcategoryOf(String parentName);

  /// English UI message used by shell/topic_category_selector.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose subcategory of {parentName}'**
  String chooseSubcategoryOf(String parentName);

  /// English UI message used by shell/topic_category_selector.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Subcategory'**
  String get subcategoryTopiccategoryselector;

  /// English UI message used by shell/topic_category_selector.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Subcategories of {parentName}'**
  String subcategoriesOf(String parentName);

  /// English UI message used by shell/topic_category_selector.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Filter {noun}'**
  String filterTopiccategoryselector(String noun);

  /// English UI message used by shell/topic_category_selector.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No matching {noun}.'**
  String noMatching(String noun);

  /// English UI message used by shell/conversation_topic_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Private conversation'**
  String get privateConversation;

  /// English UI message used by shell/conversation_topic_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Last post by {username} · '**
  String lastPostBy(String username);

  /// English UI message used by shell/conversation_topic_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Last post by {username}'**
  String lastPostByConversationtopiccard(String username);

  /// English UI message used by shell/conversation_topic_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Last post by '**
  String get lastPostByConversationtopiccardValue;

  /// English UI message used by shell/conversation_topic_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{orderColumn, select, true{{label}, sort by {viewsViewsLabel}, {ascendingAscendingDescending}} other{{label}, sort by {viewsViewsLabel}, unsorted}}'**
  String sortByConversationtopiccard(
    String orderColumn,
    String label,
    String viewsViewsLabel,
    String ascendingAscendingDescending,
  );

  /// English UI message used by shell/youtube_video.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open on YouTube: {dataTitle}'**
  String openOnYouTube(String dataTitle);

  /// English UI message used by shell/youtube_video.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open on YouTube'**
  String get openOnYouTubeYoutubevideo;

  /// English UI message used by shell/youtube_video.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load the YouTube player.'**
  String get couldnTLoadTheYouTubePlayer;

  /// English UI message used by shell/youtube_video.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'YouTube player: {dataTitle}'**
  String youTubePlayer(String dataTitle);

  /// English UI message used by shell/empty_state.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No sites yet'**
  String get noSitesYet;

  /// English UI message used by shell/empty_state.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Connect a Discourse forum to get started.'**
  String get connectADiscourseForumToGetStarted;

  /// English UI message used by shell/empty_state.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add a site'**
  String get addASite;

  /// English UI message used by shell/topic_progress.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic progress'**
  String get topicProgress;

  /// English UI message used by shell/topic_progress.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic progress, post {boundedPosition} of {boundedTotal}'**
  String topicProgressPostOf(String boundedPosition, String boundedTotal);

  /// English UI message used by shell/topic_progress.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Post navigation'**
  String get postNavigation;

  /// English UI message used by shell/topic_progress.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Close and reopen topic progress to jump in the current topic.'**
  String get closeAndReopenTopicProgressToJumpInTheCurrentTopic;

  /// English UI message used by shell/topic_progress.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not open that post. Try again.'**
  String get couldNotOpenThatPostTryAgain;

  /// English UI message used by shell/topic_progress.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Post {selected} '**
  String postTopicprogress(String selected);

  /// English UI message used by shell/topic_progress.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'First post'**
  String get firstPost;

  /// English UI message used by shell/topic_progress.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Post {valueRound} of {total}'**
  String postOf(String valueRound, String total);

  /// English UI message used by shell/message_inbox_title.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Private messages sent directly to you'**
  String get privateMessagesSentDirectlyToYou;

  /// English UI message used by shell/message_inbox_title.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Private messages sent to @{group}'**
  String privateMessagesSentTo(String group);

  /// English UI message used by shell/composer_selection_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Text formatting'**
  String get textFormatting;

  /// English UI message used by shell/composer_selection_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get underline;

  /// English UI message used by shell/composer_selection_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Clear formatting'**
  String get clearFormatting;

  /// English UI message used by shell/composer_selection_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Strikethrough'**
  String get strikethrough;

  /// English UI message used by shell/composer_selection_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'More formatting'**
  String get moreFormatting;

  /// English UI message used by shell/composer_selection_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Superscript'**
  String get superscript;

  /// English UI message used by shell/composer_selection_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Subscript'**
  String get subscript;

  /// English UI message used by shell/composer_selection_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Keyboard key'**
  String get keyboardKey;

  /// English UI message used by shell/composer_blocks.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Paragraph'**
  String get paragraph;

  /// English UI message used by shell/composer_blocks.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Divider'**
  String get divider;

  /// English UI message used by shell/composer_blocks.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get block;

  /// English UI message used by shell/composer_blocks.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Source block'**
  String get sourceBlock;

  /// English UI message used by shell/post_notice_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This staff notice will be shown above the post.'**
  String get thisStaffNoticeWillBeShownAboveThePost;

  /// English UI message used by shell/post_notice_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Notice'**
  String get notice;

  /// English UI message used by shell/post_notice_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Delete notice'**
  String get deleteNotice;

  /// English UI message used by shell/forum_appearance_settings.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not save changes.'**
  String get couldNotSaveChanges;

  /// English UI message used by shell/forum_appearance_settings.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// English UI message used by shell/forum_appearance_settings.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Applies to {forumName} only.'**
  String appliesToOnly(String forumName);

  /// English UI message used by shell/forum_appearance_settings.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Use on every forum'**
  String get useOnEveryForum;

  /// English UI message used by shell/forum_appearance_settings.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Every forum now uses these colours.'**
  String get everyForumNowUsesTheseColours;

  /// English UI message used by shell/forum_appearance_settings.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Appearance mode'**
  String get appearanceMode;

  /// English UI message used by shell/forum_appearance_settings.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get auto;

  /// English UI message used by shell/instance_rail.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Select a forum to toggle its sidebar'**
  String get selectAForumToToggleItsSidebar;

  /// English UI message used by shell/instance_rail.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Collapse sidebar'**
  String get collapseSidebar;

  /// English UI message used by shell/instance_rail.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Expand sidebar'**
  String get expandSidebar;

  /// English UI message used by shell/instance_rail.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t save the new site order. Try again.'**
  String get couldnTSaveTheNewSiteOrderTryAgain;

  /// English UI message used by shell/instance_rail.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'All forums'**
  String get allForums;

  /// English UI message used by shell/instance_rail.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Retry loading sites'**
  String get retryLoadingSites;

  /// English UI message used by shell/instance_rail.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open component styleguide'**
  String get openComponentStyleguide;

  /// English UI message used by shell/instance_rail.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnostics;

  /// English UI message used by shell/instance_rail.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{unseen, plural, =1{Diagnostics, {unseen} unseen error} other{Diagnostics, {unseen} unseen errors}}'**
  String diagnosticsUnseen(num unseen);

  /// English UI message used by shell/instance_rail.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Update to {version}'**
  String updateTo(String version);

  /// English UI message used by shell/instance_rail.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Restart to finish updating'**
  String get restartToFinishUpdating;

  /// English UI message used by shell/instance_rail.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The last update check failed'**
  String get theLastUpdateCheckFailed;

  /// English UI message used by shell/instance_rail.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get checkForUpdates;

  /// English UI message used by shell/instance_rail.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'unread notification'**
  String get unreadNotification;

  /// English UI message used by shell/instance_rail.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add a Discourse site'**
  String get addADiscourseSite;

  /// English UI message used by shell/bookmark_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Other bookmarks'**
  String get otherBookmarks;

  /// English UI message used by shell/bookmark_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading bookmarks'**
  String get loadingBookmarks;

  /// English UI message used by shell/bookmark_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Nothing bookmarked yet.'**
  String get nothingBookmarkedYet;

  /// English UI message used by shell/bookmark_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No bookmarks in this filter.'**
  String get noBookmarksInThisFilter;

  /// English UI message used by shell/bookmark_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading more bookmarks'**
  String get loadingMoreBookmarks;

  /// English UI message used by shell/bookmark_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Filter bookmarks'**
  String get filterBookmarks;

  /// English UI message used by shell/bookmark_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'All bookmarks'**
  String get allBookmarks;

  /// English UI message used by shell/bookmark_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Note: {name}'**
  String noteBookmarklist(String name);

  /// English UI message used by shell/post_revision_history.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit history (last 100 revisions)'**
  String get editHistoryLast100Revisions;

  /// English UI message used by shell/post_revision_history.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit history'**
  String get editHistory;

  /// English UI message used by shell/post_revision_history.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'1 edit'**
  String get message1Edit;

  /// English UI message used by shell/post_revision_history.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{ageNow, select, true{Last edited now} other{Last edited {age} ago}}'**
  String lastEdited(String ageNow, String age);

  /// English UI message used by shell/post_revision_history.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Your connection changed. Reopen edit history and try again.'**
  String get yourConnectionChangedReopenEditHistoryAndTryAgain;

  /// English UI message used by shell/post_revision_history.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load edit history.'**
  String get couldnTLoadEditHistory;

  /// English UI message used by shell/post_revision_history.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading revision'**
  String get loadingRevision;

  /// English UI message used by shell/post_revision_history.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reply to'**
  String get replyToPostrevisionhistory;

  /// English UI message used by shell/post_revision_history.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Wiki'**
  String get wiki;

  /// English UI message used by shell/post_revision_history.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic type'**
  String get topicType;

  /// English UI message used by shell/post_revision_history.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Featured link'**
  String get featuredLink;

  /// English UI message used by shell/post_revision_history.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This revision is too complex to compare.'**
  String get thisRevisionIsTooComplexToCompare;

  /// English UI message used by shell/post_revision_history.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The post body did not change in this revision.'**
  String get thePostBodyDidNotChangeInThisRevision;

  /// English UI message used by shell/post_revision_history.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// English UI message used by shell/post_revision_history.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Regular'**
  String get regular;

  /// English UI message used by shell/post_revision_history.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Moderator'**
  String get moderator;

  /// English UI message used by shell/post_revision_history.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Type {value}'**
  String type(String value);

  /// English UI message used by shell/post_revision_history.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Inline'**
  String get inline;

  /// English UI message used by shell/post_revision_history.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Side by side'**
  String get sideBySide;

  /// English UI message used by shell/post_revision_history.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get current;

  /// English UI message used by shell/post_revision_history.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unknown editor'**
  String get unknownEditor;

  /// English UI message used by shell/post_revision_history.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The differences in this revision are hidden.'**
  String get theDifferencesInThisRevisionAreHidden;

  /// English UI message used by shell/post_revision_history.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'First'**
  String get first;

  /// English UI message used by shell/forum_search.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search this forum'**
  String get searchThisForum;

  /// English UI message used by shell/global_search_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search could not load. Please try again.'**
  String get searchCouldNotLoadPleaseTryAgain;

  /// English UI message used by shell/global_search_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The search timed out. Please try again.'**
  String get theSearchTimedOutPleaseTryAgain;

  /// English UI message used by shell/global_search_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The forum is busy. Please try again.'**
  String get theForumIsBusyPleaseTryAgain;

  /// English UI message used by shell/global_search_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Too many searches. Wait a moment before trying again.'**
  String get tooManySearchesWaitAMomentBeforeTryingAgain;

  /// English UI message used by shell/global_search_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search is unavailable.'**
  String get searchIsUnavailable;

  /// English UI message used by shell/global_search_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search is too long.'**
  String get searchIsTooLong;

  /// English UI message used by shell/global_search_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Use a filter from the selected search type.'**
  String get useAFilterFromTheSelectedSearchType;

  /// English UI message used by shell/global_search_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search page is out of range.'**
  String get searchPageIsOutOfRange;

  /// English UI message used by shell/global_search_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topics, users and groups could not load.'**
  String get topicsUsersAndGroupsCouldNotLoad;

  /// English UI message used by shell/global_search_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{scopeLabel} search could not load.'**
  String searchCouldNotLoadGlobalsearchapi(String scopeLabel);

  /// English UI message used by shell/global_search_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unsupported search result.'**
  String get unsupportedSearchResult;

  /// English UI message used by shell/global_search_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Use a shorter category name.'**
  String get useAShorterCategoryName;

  /// English UI message used by shell/global_search_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Category search is unavailable.'**
  String get categorySearchIsUnavailable;

  /// English UI message used by shell/global_search_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'More categories couldn’t load.'**
  String get moreCategoriesCouldnTLoad;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load this topic.'**
  String get couldnTLoadThisTopic;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Delete selected posts?'**
  String get deleteSelectedPosts;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Delete {count} selected post?} other{Delete {count} selected posts?}}'**
  String deleteSelected(num count);

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Merge selected posts?'**
  String get mergeSelectedPosts;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Merge {count} posts by the same author into one post?'**
  String mergePostsByTheSameAuthorIntoOnePost(String count);

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get merge;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Select all loaded'**
  String get selectAllLoaded;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading topic'**
  String get loadingTopic;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'More topics'**
  String get moreTopics;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Hide topic sidebar'**
  String get hideTopicSidebar;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Show topic sidebar'**
  String get showTopicSidebar;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading more topics'**
  String get loadingMoreTopics;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'View 1 hidden reply'**
  String get view1HiddenReply;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'View {count} hidden replies'**
  String viewHiddenReplies(String count);

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading earlier posts'**
  String get loadingEarlierPosts;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Select post by {postUsername}'**
  String selectPostBy(String postUsername);

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This post is a private whisper'**
  String get thisPostIsAPrivateWhisper;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This is the first time {postUsername} has posted — let’s welcome them to our community!'**
  String thisIsTheFirstTimeHasPostedLetSWelcomeThem(String postUsername);

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'It’s been a while since we’ve seen {postUsername} — welcome back!'**
  String itSBeenAWhileSinceWeVeSeenWelcomeBack(String postUsername);

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Staff notice'**
  String get staffNotice;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic views'**
  String get topicViews;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Likes in this topic'**
  String get likesInThisTopic;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Links in this topic'**
  String get linksInThisTopic;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get showAllTopicview;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading more posts'**
  String get loadingMorePosts;

  /// English UI message used by shell/site_image.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Pause GIF'**
  String get pauseGIF;

  /// English UI message used by shell/site_image.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Play GIF'**
  String get playGIF;

  /// English UI message used by shell/site_image.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Site image is unavailable: {url}'**
  String siteImageIsUnavailable(String url);

  /// English UI message used by shell/forum_theme_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit {themeName}'**
  String editForumthemepicker(String themeName);

  /// English UI message used by shell/forum_theme_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Create theme based on {forumName}'**
  String createThemeBasedOn(String forumName);

  /// English UI message used by shell/forum_theme_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Create theme based on {optionName}'**
  String createThemeBasedOnForumthemepicker(String optionName);

  /// English UI message used by shell/composer_presentation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Composer'**
  String get composer;

  /// English UI message used by shell/composer_presentation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Resize composer'**
  String get resizeComposer;

  /// English UI message used by shell/topic_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{topicBookmarksLength, plural, =1{Manage {topicBookmarksLength} topic bookmark} other{Manage {topicBookmarksLength} topic bookmarks}}'**
  String manageTopicBookmark(num topicBookmarksLength);

  /// English UI message used by shell/topic_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Bookmark this topic'**
  String get bookmarkThisTopic;

  /// English UI message used by shell/topic_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Share topic'**
  String get shareTopic;

  /// English UI message used by shell/topic_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Delete topic?'**
  String get deleteTopic;

  /// English UI message used by shell/topic_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This removes the topic and all of its replies. Staff may be able to recover it later.'**
  String get thisRemovesTheTopicAndAllOfItsRepliesStaffMay;

  /// English UI message used by shell/topic_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Flag topic'**
  String get flagTopicTopicactions;

  /// English UI message used by shell/topic_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unpin topic'**
  String get unpinTopic;

  /// English UI message used by shell/topic_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Pin topic'**
  String get pinTopic;

  /// English UI message used by shell/topic_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Select posts'**
  String get selectPosts;

  /// English UI message used by shell/topic_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open topic'**
  String get openTopic;

  /// English UI message used by shell/topic_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Close topic'**
  String get closeTopic;

  /// English UI message used by shell/topic_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unarchive topic'**
  String get unarchiveTopic;

  /// English UI message used by shell/topic_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Archive topic'**
  String get archiveTopic;

  /// English UI message used by shell/topic_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Make topic unlisted'**
  String get makeTopicUnlisted;

  /// English UI message used by shell/topic_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Make topic visible'**
  String get makeTopicVisible;

  /// English UI message used by shell/topic_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Delete topic'**
  String get deleteTopicTopicactions;

  /// English UI message used by shell/topic_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Recover topic'**
  String get recoverTopic;

  /// English UI message used by shell/topic_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'More topic actions'**
  String get moreTopicActions;

  /// English UI message used by shell/topic_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic notifications'**
  String get topicNotifications;

  /// English UI message used by shell/forum_display_settings.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not save the icon set.'**
  String get couldNotSaveTheIconSet;

  /// English UI message used by shell/forum_display_settings.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Icons'**
  String get icons;

  /// English UI message used by shell/forum_display_settings.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Content width'**
  String get contentWidth;

  /// English UI message used by shell/forum_display_settings.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Wide'**
  String get wide;

  /// English UI message used by shell/users_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get userUserspage;

  /// English UI message used by shell/users_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Filter users'**
  String get filterUsers;

  /// English UI message used by shell/users_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Filter by group'**
  String get filterByGroup;

  /// English UI message used by shell/users_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No groups found.'**
  String get noGroupsFound;

  /// English UI message used by shell/users_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Directory unavailable'**
  String get directoryUnavailable;

  /// English UI message used by shell/invites_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load invites. Please try again.'**
  String get couldnTLoadInvitesPleaseTryAgain;

  /// English UI message used by shell/invites_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invite removed.'**
  String get inviteRemoved;

  /// English UI message used by shell/invites_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t save the invite. Please try again.'**
  String get couldnTSaveTheInvitePleaseTryAgain;

  /// English UI message used by shell/groups_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load more groups.'**
  String get couldnTLoadMoreGroups;

  /// English UI message used by shell/groups_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load the group directory.'**
  String get couldnTLoadTheGroupDirectory;

  /// English UI message used by shell/groups_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load this group.'**
  String get couldnTLoadThisGroup;

  /// English UI message used by shell/groups_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load more members.'**
  String get couldnTLoadMoreMembers;

  /// English UI message used by shell/groups_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load group members.'**
  String get couldnTLoadGroupMembers;

  /// English UI message used by shell/groups_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load more requests.'**
  String get couldnTLoadMoreRequests;

  /// English UI message used by shell/groups_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load membership requests.'**
  String get couldnTLoadMembershipRequests;

  /// English UI message used by shell/groups_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load more activity.'**
  String get couldnTLoadMoreActivity;

  /// English UI message used by shell/groups_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load group activity.'**
  String get couldnTLoadGroupActivity;

  /// English UI message used by shell/groups_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load group permissions.'**
  String get couldnTLoadGroupPermissions;

  /// English UI message used by shell/groups_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load more group logs.'**
  String get couldnTLoadMoreGroupLogs;

  /// English UI message used by shell/groups_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load group logs.'**
  String get couldnTLoadGroupLogs;

  /// English UI message used by shell/small_action.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'closed this topic'**
  String get closedThisTopic;

  /// English UI message used by shell/small_action.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'opened this topic'**
  String get openedThisTopic;

  /// English UI message used by shell/small_action.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'archived this topic'**
  String get archivedThisTopic;

  /// English UI message used by shell/small_action.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'unarchived this topic'**
  String get unarchivedThisTopic;

  /// English UI message used by shell/small_action.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'pinned this topic'**
  String get pinnedThisTopic;

  /// English UI message used by shell/small_action.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'unpinned this topic'**
  String get unpinnedThisTopic;

  /// English UI message used by shell/small_action.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'pinned this topic globally'**
  String get pinnedThisTopicGlobally;

  /// English UI message used by shell/small_action.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'unpinned this topic globally'**
  String get unpinnedThisTopicGlobally;

  /// English UI message used by shell/small_action.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'made this topic a banner'**
  String get madeThisTopicABanner;

  /// English UI message used by shell/small_action.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'removed this banner'**
  String get removedThisBanner;

  /// English UI message used by shell/small_action.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'listed this topic'**
  String get listedThisTopic;

  /// English UI message used by shell/small_action.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'unlisted this topic'**
  String get unlistedThisTopic;

  /// English UI message used by shell/small_action.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'split this topic'**
  String get splitThisTopic;

  /// English UI message used by shell/small_action.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'moved this post'**
  String get movedThisPost;

  /// English UI message used by shell/small_action.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'removed themselves from this message'**
  String get removedThemselvesFromThisMessage;

  /// English UI message used by shell/small_action.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'automatically bumped this topic'**
  String get automaticallyBumpedThisTopic;

  /// English UI message used by shell/small_action.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'made this topic public'**
  String get madeThisTopicPublic;

  /// English UI message used by shell/small_action.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'made this topic a personal message'**
  String get madeThisTopicAPersonalMessage;

  /// English UI message used by shell/small_action.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'converted this to a topic'**
  String get convertedThisToATopic;

  /// English UI message used by shell/small_action.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'forwarded the above email'**
  String get forwardedTheAboveEmail;

  /// English UI message used by shell/stream_day_separator.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Go to start of {label}'**
  String goToStartOf(String label);

  /// English UI message used by shell/do_not_disturb_dialog.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not open notification preferences.'**
  String get couldNotOpenNotificationPreferences;

  /// English UI message used by shell/do_not_disturb_dialog.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Pause notifications for…'**
  String get pauseNotificationsFor;

  /// English UI message used by shell/do_not_disturb_dialog.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Set a notification schedule'**
  String get setANotificationSchedule;

  /// English UI message used by shell/update_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'App updates'**
  String get appUpdates;

  /// English UI message used by shell/update_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Discourse Native'**
  String get discourseNative;

  /// English UI message used by shell/update_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Discourse Native {updatesRunningVersion}'**
  String discourseNativeUpdatesheet(String updatesRunningVersion);

  /// English UI message used by shell/update_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Following the {updatesChannelLabel} channel.'**
  String followingTheChannel(String updatesChannelLabel);

  /// English UI message used by shell/update_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You\'\'re up to date.'**
  String get youReUpToDate;

  /// English UI message used by shell/update_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Switch to {releaseVersion}'**
  String switchTo(String releaseVersion);

  /// English UI message used by shell/update_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Download {releaseVersion}'**
  String downloadUpdatesheet(String releaseVersion);

  /// English UI message used by shell/update_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Ready to install.'**
  String get readyToInstall;

  /// English UI message used by shell/update_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The app will close and reopen.'**
  String get theAppWillCloseAndReopen;

  /// English UI message used by shell/update_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Restart and install'**
  String get restartAndInstall;

  /// English UI message used by shell/update_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Installing update'**
  String get installingUpdate;

  /// English UI message used by shell/update_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Installing…'**
  String get installing;

  /// English UI message used by shell/update_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The update could not be checked.'**
  String get theUpdateCouldNotBeChecked;

  /// English UI message used by shell/update_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open the releases page'**
  String get openTheReleasesPage;

  /// English UI message used by shell/update_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Never checked for updates.'**
  String get neverCheckedForUpdates;

  /// English UI message used by shell/update_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Checked just now.'**
  String get checkedJustNow;

  /// English UI message used by shell/update_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Last checked {ago} ago.'**
  String lastCheckedAgo(String ago);

  /// English UI message used by shell/update_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates'**
  String get checkingForUpdates;

  /// English UI message used by shell/update_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Version {releaseVersion} is on this channel.'**
  String versionIsOnThisChannel(String releaseVersion);

  /// English UI message used by shell/update_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Version {releaseVersion} is available.'**
  String versionIsAvailable(String releaseVersion);

  /// English UI message used by shell/update_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Downloading update'**
  String get downloadingUpdate;

  /// English UI message used by shell/update_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Download in progress.'**
  String get downloadInProgress;

  /// English UI message used by shell/update_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Downloading — {progressRound}%'**
  String downloadingUpdatesheet(String progressRound);

  /// English UI message used by shell/composer_document/selection.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'ComposerRangeSelection({anchor}, {focus})'**
  String composerRangeSelection(String anchor, String focus);

  /// English UI message used by shell/reaction_presentation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'1 reaction'**
  String get message1Reaction;

  /// English UI message used by shell/reaction_presentation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'show who reacted'**
  String get showWhoReacted;

  /// English UI message used by shell/reaction_presentation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading reactions'**
  String get loadingReactions;

  /// English UI message used by shell/cooked_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Column {index}'**
  String columnCookedtable(String index);

  /// English UI message used by shell/cooked_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Table copied'**
  String get tableCopied;

  /// English UI message used by shell/cooked_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Copy table'**
  String get copyTable;

  /// English UI message used by shell/add_instance_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t save this site. Try again.'**
  String get couldnTSaveThisSiteTryAgain;

  /// English UI message used by shell/add_instance_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{instanceTitle} is already in your list.'**
  String isAlreadyInYourList(String instanceTitle);

  /// English UI message used by shell/add_instance_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t reach {term}.'**
  String couldnTReachAddinstancesheet(String term);

  /// English UI message used by shell/add_instance_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Valid Discourse site'**
  String get validDiscourseSite;

  /// English UI message used by shell/add_instance_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Site is unavailable or is not a Discourse forum'**
  String get siteIsUnavailableOrIsNotADiscourseForum;

  /// English UI message used by shell/add_instance_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter the address of a Discourse forum.'**
  String get enterTheAddressOfADiscourseForum;

  /// English UI message used by shell/add_instance_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Forum address'**
  String get forumAddress;

  /// English UI message used by shell/add_instance_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// English UI message used by shell/composer_quotes.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Read only. Use the remove quote button to delete it.'**
  String get readOnlyUseTheRemoveQuoteButtonToDeleteIt;

  /// English UI message used by shell/composer_quotes.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove quote'**
  String get removeQuote;

  /// English UI message used by shell/user_directory_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load more users.'**
  String get couldnTLoadMoreUsers;

  /// English UI message used by shell/user_directory_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load the user directory.'**
  String get couldnTLoadTheUserDirectory;

  /// English UI message used by shell/main_content.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Resize message list'**
  String get resizeMessageList;

  /// English UI message used by shell/main_content.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Resize topic list'**
  String get resizeTopicList;

  /// English UI message used by shell/main_content.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open {routeTitle} details'**
  String openDetailsMaincontent(String routeTitle);

  /// English UI message used by shell/main_content.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'1 group'**
  String get message1Group;

  /// English UI message used by shell/main_content.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Sign in to view your messages'**
  String get signInToViewYourMessages;

  /// English UI message used by shell/main_content.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Private messages are tied to your forum account and aren’t available while you’re signed out.'**
  String get privateMessagesAreTiedToYourForumAccountAndArenT;

  /// English UI message used by shell/main_content.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get notFound;

  /// English UI message used by shell/main_content.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The requested page could not be found.'**
  String get theRequestedPageCouldNotBeFound;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add search filter'**
  String get addSearchFilter;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit {editorLabel} condition'**
  String editCondition(String editorLabel);

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add filter'**
  String get addFilter;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove {definitionLabel} condition'**
  String removeCondition(String definitionLabel);

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search filters'**
  String get searchFilters;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add filter…'**
  String get addFilterGlobalsearchfilterpicker;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Find a search filter'**
  String get findASearchFilter;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No filters match your search.'**
  String get noFiltersMatchYourSearch;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load tags'**
  String get couldnTLoadTagsGlobalsearchfilterpicker;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t refresh tags'**
  String get couldnTRefreshTags;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Suggestions could not load.'**
  String get suggestionsCouldNotLoad;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Back to filters'**
  String get backToFilters;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Match topics that'**
  String get matchTopicsThat;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Apply changes'**
  String get applyChanges;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Add condition'**
  String get addCondition;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Include any selected tag'**
  String get includeAnySelectedTag;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Include every selected tag'**
  String get includeEverySelectedTag;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Exclude any selected tag'**
  String get excludeAnySelectedTag;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Exclude this combination'**
  String get excludeThisCombination;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove {controllerFilterValue}'**
  String removeGlobalsearchfilterpicker(String controllerFilterValue);

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Available tags'**
  String get availableTags;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search available tags…'**
  String get searchAvailableTags;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search available tags'**
  String get searchAvailableTagsGlobalsearchfilterpicker;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Selected · {valuesLength}'**
  String selectedGlobalsearchfilterpicker(String valuesLength);

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Showing saved tags. More may be available.'**
  String get showingSavedTagsMoreMayBeAvailable;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Try again to see available tags.'**
  String get tryAgainToSeeAvailableTags;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Saved tags'**
  String get savedTags;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Matching tags'**
  String get matchingTags;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Tag suggestions'**
  String get tagSuggestions;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Finding tags…'**
  String get findingTags;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No saved tags match'**
  String get noSavedTagsMatch;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No tags match'**
  String get noTagsMatch;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Find an option…'**
  String get findAnOption;

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Use “{queryTrim}”'**
  String use(String queryTrim);

  /// English UI message used by shell/global_search_category_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Categories couldn’t load.'**
  String get categoriesCouldnTLoad;

  /// English UI message used by shell/global_search_category_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading categories…'**
  String get loadingCategories;

  /// English UI message used by shell/global_search_category_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Categories unavailable'**
  String get categoriesUnavailable;

  /// English UI message used by shell/global_search_category_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'All categories · {choicesLength}'**
  String allCategories(String choicesLength);

  /// English UI message used by shell/global_search_category_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search all categories'**
  String get searchAllCategories;

  /// English UI message used by shell/global_search_category_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search all categories…'**
  String get searchAllCategoriesGlobalsearchcategoryeditor;

  /// English UI message used by shell/global_search_category_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Clear category search'**
  String get clearCategorySearch;

  /// English UI message used by shell/global_search_category_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No categories available.'**
  String get noCategoriesAvailable;

  /// English UI message used by shell/global_search_category_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No matching categories.'**
  String get noMatchingCategories;

  /// English UI message used by shell/global_search_category_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Show all categories'**
  String get showAllCategories;

  /// English UI message used by shell/global_search_category_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Load more categories'**
  String get loadMoreCategories;

  /// English UI message used by shell/global_search_category_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose one or more categories.'**
  String get chooseOneOrMoreCategories;

  /// English UI message used by shell/global_search_category_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Remove {labelValue}'**
  String removeGlobalsearchcategoryeditor(String labelValue);

  /// English UI message used by shell/global_search_category_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Include subcategories'**
  String get includeSubcategoriesGlobalsearchcategoryeditor;

  /// English UI message used by shell/composer_discard.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This draft could not be saved yet. Please try again.'**
  String get thisDraftCouldNotBeSavedYetPleaseTryAgain;

  /// English UI message used by shell/composer_discard.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Finish the current operation before closing this draft.'**
  String get finishTheCurrentOperationBeforeClosingThisDraft;

  /// English UI message used by shell/composer_discard.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This draft changed while the confirmation was open. Cancel, review it, and try again.'**
  String get thisDraftChangedWhileTheConfirmationWasOpenCancelReviewIt;

  /// English UI message used by shell/composer_discard.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Do you want to discard your changes?'**
  String get doYouWantToDiscardYourChanges;

  /// English UI message used by shell/composer_discard.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Do you want to discard your post?'**
  String get doYouWantToDiscardYourPost;

  /// English UI message used by shell/composer_discard.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Discard changes'**
  String get discardChanges;

  /// English UI message used by shell/post_fast_edit.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Selected text'**
  String get selectedText;

  /// English UI message used by shell/post_fast_edit.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Save Edit'**
  String get saveEditPostfastedit;

  /// English UI message used by shell/forum_theme_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'All themes'**
  String get allThemes;

  /// English UI message used by shell/forum_theme_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Name this theme'**
  String get nameThisTheme;

  /// English UI message used by shell/forum_theme_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Accent'**
  String get accent;

  /// English UI message used by shell/forum_theme_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get highlight;

  /// English UI message used by shell/forum_theme_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get success;

  /// English UI message used by shell/forum_theme_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Attention'**
  String get attention;

  /// English UI message used by shell/forum_theme_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Starts from the theme in use. Name it to keep it.'**
  String get startsFromTheThemeInUseNameItToKeepIt;

  /// English UI message used by shell/forum_theme_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Create theme'**
  String get createTheme;

  /// English UI message used by shell/forum_theme_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Save theme'**
  String get saveTheme;

  /// English UI message used by shell/forum_theme_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{label} colour palette'**
  String colourPalette(String label);

  /// English UI message used by shell/forum_theme_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{label} hex colour'**
  String hexColour(String label);

  /// English UI message used by shell/forum_theme_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose {label} colour'**
  String chooseColour(String label);

  /// English UI message used by shell/forum_theme_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Use #RRGGBB.'**
  String get useRRGGBB;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Errors'**
  String get errors;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search diagnostics'**
  String get searchDiagnostics;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Severity'**
  String get severity;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Event copied'**
  String get eventCopied;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Filtered report copied'**
  String get filteredReportCopied;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Clear diagnostics history?'**
  String get clearDiagnosticsHistory;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This removes the recorded requests and errors from this device. Requests already in progress will not be restored afterward.'**
  String get thisRemovesTheRecordedRequestsAndErrorsFromThisDeviceRequests;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Back to diagnostics'**
  String get backToDiagnostics;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Event details'**
  String get eventDetails;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Resume live updates'**
  String get resumeLiveUpdates;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Freeze visible events'**
  String get freezeVisibleEvents;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Copy filtered report'**
  String get copyFilteredReport;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Close diagnostics'**
  String get closeDiagnostics;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get general;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Scroll performance'**
  String get scrollPerformance;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Scroll performance capture'**
  String get scrollPerformanceCapture;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Record scrolling in a topic, topic list or users directory, then copy a performance report to share for investigation. The capture stays in memory and never includes post bodies, titles, site URLs, or credentials.'**
  String get recordScrollingInATopicTopicListOrUsersDirectoryThen;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Close Diagnostics, reproduce the issue in a topic, topic list or users directory, then return here and stop the capture. Scroll for 5–10 seconds, then wait a second for frame timings before stopping. Recording stops automatically after {controllerMaximumDurationInMinutes} minutes or {controllerMaximumEvents} events.'**
  String closeDiagnosticsReproduceTheIssueInATopicTopicListOr(
    String controllerMaximumDurationInMinutes,
    String controllerMaximumEvents,
  );

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Stop capture'**
  String get stopCapture;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Copy performance report'**
  String get copyPerformanceReport;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Copy full JSON capture'**
  String get copyFullJSONCapture;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Start a new capture'**
  String get startANewCapture;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Discard capture'**
  String get discardCapture;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The trace includes topic-list row builds and scroll bookkeeping, topic scroll notifications, post-sliver visible range and geometry update, paging and anchor decision, row layout cost, viewport bookkeeping cost, and Flutter frame timing. The performance report summarizes slow frames and the most expensive posts without copying the full event log.'**
  String get theTraceIncludesTopicListRowBuildsAndScrollBookkeepingTopic;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Start capture'**
  String get startCapture;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Performance report copied'**
  String get performanceReportCopied;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Scroll capture copied'**
  String get scrollCaptureCopied;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{stateEventCount} events over {secondsToStringAsFixed}s\n{stateTopicEventCount} topic events · {stateFrameCount} frames\n{stateSlowBuildFrameCount} slow builds · {stateSlowRasterFrameCount} slow rasters\nBudget: {stateFrameBudgetMicrosecondsToStringAsFi} ms at {stateDisplayRefreshRateToStringAsFixed} Hz'**
  String eventsOverSTopicEventsFramesSlowBuildsSlowRastersBudget(
    String stateEventCount,
    String secondsToStringAsFixed,
    String stateTopicEventCount,
    String stateFrameCount,
    String stateSlowBuildFrameCount,
    String stateSlowRasterFrameCount,
    String stateFrameBudgetMicrosecondsToStringAsFi,
    String stateDisplayRefreshRateToStringAsFixed,
  );

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Stopped at time limit'**
  String get stoppedAtTimeLimit;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Stopped at event limit'**
  String get stoppedAtEventLimit;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Capture ready'**
  String get captureReady;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Filter by {label}'**
  String filterBy(String label);

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No matching events'**
  String get noMatchingEvents;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No diagnostics yet'**
  String get noDiagnosticsYet;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Change the filters or search to see more.'**
  String get changeTheFiltersOrSearchToSeeMore;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Requests, logs, and operational errors will appear here.'**
  String get requestsLogsAndOperationalErrorsWillAppearHere;

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Session {stateName}'**
  String session(String stateName);

  /// English UI message used by shell/topic_list_bottom_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Previous message'**
  String get previousMessage;

  /// English UI message used by shell/topic_list_bottom_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Next message'**
  String get nextMessage;

  /// English UI message used by shell/topic_list_bottom_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dismiss new topics'**
  String get dismissNewTopics;

  /// English UI message used by shell/topic_list_bottom_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dismiss new replies'**
  String get dismissNewReplies;

  /// English UI message used by shell/topic_list_bottom_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dismiss New'**
  String get dismissNew;

  /// English UI message used by shell/user_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'View profile for @{username}'**
  String viewProfileForUsercard(String username);

  /// English UI message used by shell/user_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Profile preview unavailable.'**
  String get profilePreviewUnavailable;

  /// English UI message used by shell/user_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Profile for @{username}'**
  String profileFor(String username);

  /// English UI message used by shell/user_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading profile'**
  String get loadingProfile;

  /// English UI message used by shell/user_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'View profile'**
  String get viewProfile;

  /// English UI message used by shell/user_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Time read'**
  String get timeRead;

  /// English UI message used by shell/image_decode.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Image of {width}x{height} pixels exceeds the decode limit'**
  String imageOfXPixelsExceedsTheDecodeLimit(String width, String height);

  /// English UI message used by shell/user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invites'**
  String get invites;

  /// English UI message used by shell/user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get other;

  /// English UI message used by shell/user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Set a custom status'**
  String get setACustomStatus;

  /// English UI message used by shell/user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Pause notifications'**
  String get pauseNotifications;

  /// English UI message used by shell/user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Drafts'**
  String get drafts;

  /// English UI message used by shell/user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// English UI message used by shell/user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Notifications paused'**
  String get notificationsPaused;

  /// English UI message used by shell/user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offline;

  /// English UI message used by shell/user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Presence unavailable'**
  String get presenceUnavailable;

  /// English UI message used by shell/user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Status and notifications'**
  String get statusAndNotifications;

  /// English UI message used by shell/user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Status and notifications, {label}'**
  String statusAndNotificationsUsermenu(String label);

  /// English UI message used by shell/user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Saving'**
  String get savingUsermenu;

  /// English UI message used by shell/user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'On, no expiration'**
  String get onNoExpiration;

  /// English UI message used by shell/user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'On, until {localizationsFormatMediumDateUntil} {clockTimeLabelContextUntil}'**
  String onUntil(
    String localizationsFormatMediumDateUntil,
    String clockTimeLabelContextUntil,
  );

  /// English UI message used by shell/user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Loading presence…'**
  String get loadingPresence;

  /// English UI message used by shell/user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Presence'**
  String get presence;

  /// English UI message used by shell/user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Retry loading the presence setting'**
  String get retryLoadingThePresenceSetting;

  /// English UI message used by shell/user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Toggle presence features'**
  String get togglePresenceFeatures;

  /// English UI message used by shell/user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This site is no longer available.'**
  String get thisSiteIsNoLongerAvailable;

  /// English UI message used by shell/user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This account is no longer connected.'**
  String get thisAccountIsNoLongerConnected;

  /// English UI message used by shell/user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This section is no longer available.'**
  String get thisSectionIsNoLongerAvailable;

  /// English UI message used by shell/topic_share.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Continue the discussion from [{escaped}]({url})'**
  String continueTheDiscussionFrom(String escaped, String url);

  /// English UI message used by shell/topic_share.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Share this topic'**
  String get shareThisTopic;

  /// English UI message used by shell/topic_share.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Share post #{postNumber}'**
  String sharePost(String postNumber);

  /// English UI message used by shell/topic_share.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reply as new message'**
  String get replyAsNewMessage;

  /// English UI message used by shell/topic_share.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reply as new topic'**
  String get replyAsNewTopic;

  /// English UI message used by shell/topic_share.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t open sharing.'**
  String get couldnTOpenSharing;

  /// English UI message used by shell/topic_share.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Share to another app'**
  String get shareToAnotherApp;

  /// English UI message used by shell/badges_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'All badges'**
  String get allBadges;

  /// English UI message used by shell/badges_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You earned this badge'**
  String get youEarnedThisBadge;

  /// English UI message used by shell/badges_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Can be earned multiple times'**
  String get canBeEarnedMultipleTimes;

  /// English UI message used by shell/badges_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Can be used as a title'**
  String get canBeUsedAsATitle;

  /// English UI message used by shell/badges_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Recently awarded'**
  String get recentlyAwarded;

  /// English UI message used by shell/badges_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Awarded to {routeUsername}'**
  String awardedTo(String routeUsername);

  /// English UI message used by shell/badges_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Show all recipients'**
  String get showAllRecipients;

  /// English UI message used by shell/badges_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Show your awards'**
  String get showYourAwards;

  /// English UI message used by shell/badges_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No awards to display.'**
  String get noAwardsToDisplay;

  /// English UI message used by shell/badges_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Earned'**
  String get earned;

  /// English UI message used by shell/badges_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Not earned'**
  String get notEarned;

  /// English UI message used by shell/badges_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Bronze'**
  String get bronze;

  /// English UI message used by shell/badges_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Silver'**
  String get silver;

  /// English UI message used by shell/badges_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Gold'**
  String get gold;

  /// English UI message used by shell/badges_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Filter badges'**
  String get filterBadges;

  /// English UI message used by shell/badges_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No badges to display.'**
  String get noBadgesToDisplay;

  /// English UI message used by shell/badges_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No badges match this filter.'**
  String get noBadgesMatchThisFilter;

  /// English UI message used by shell/badges_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'View awarded post'**
  String get viewAwardedPost;

  /// English UI message used by shell/user_status_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Enter a status description.'**
  String get enterAStatusDescription;

  /// English UI message used by shell/user_status_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Set custom status'**
  String get setCustomStatus;

  /// English UI message used by shell/user_status_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Choose status emoji'**
  String get chooseStatusEmoji;

  /// English UI message used by shell/user_status_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Status emoji'**
  String get statusEmoji;

  /// English UI message used by shell/user_status_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'What’s your status?'**
  String get whatSYourStatus;

  /// English UI message used by shell/user_status_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'What are you up to?'**
  String get whatAreYouUpTo;

  /// English UI message used by shell/user_status_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Clear after'**
  String get clearAfter;

  /// English UI message used by shell/user_status_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'1 hour'**
  String get message1Hour;

  /// English UI message used by shell/user_status_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'2 hours'**
  String get message2Hours;

  /// English UI message used by shell/user_status_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get tomorrow;

  /// English UI message used by shell/user_status_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Until {contextFormatMediumDateUntil} {clockTimeLabelContextUntil}'**
  String until(
    String contextFormatMediumDateUntil,
    String clockTimeLabelContextUntil,
  );

  /// English UI message used by shell/user_status_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Preview: '**
  String get preview;

  /// English UI message used by shell/user_status_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Clear status'**
  String get clearStatus;

  /// English UI message used by app_shortcuts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open next topic'**
  String get openNextTopic;

  /// English UI message used by app_shortcuts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open previous topic'**
  String get openPreviousTopic;

  /// English UI message used by app_shortcuts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Next topic in the list'**
  String get nextTopicInTheList;

  /// English UI message used by app_shortcuts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Previous topic in the list'**
  String get previousTopicInTheList;

  /// English UI message used by app_shortcuts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open highlighted topic'**
  String get openHighlightedTopic;

  /// English UI message used by app_shortcuts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Next post or topic'**
  String get nextPostOrTopic;

  /// English UI message used by app_shortcuts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Previous post or topic'**
  String get previousPostOrTopic;

  /// English UI message used by app_shortcuts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reply to selected post'**
  String get replyToSelectedPost;

  /// English UI message used by foundation/calendar_day.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'January'**
  String get january;

  /// English UI message used by foundation/calendar_day.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'February'**
  String get february;

  /// English UI message used by foundation/calendar_day.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'March'**
  String get march;

  /// English UI message used by foundation/calendar_day.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'May'**
  String get may;

  /// English UI message used by foundation/calendar_day.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'September'**
  String get september;

  /// English UI message used by foundation/calendar_day.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'December'**
  String get december;

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'New notification'**
  String get newNotification;

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'mentioned you in {title}'**
  String mentionedYouInNotificationtypes(String title);

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'replied to {title}'**
  String repliedTo(String title);

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'quoted you in {title}'**
  String quotedYouIn(String title);

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'edited your post in {title}'**
  String editedYourPostIn(String title);

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'liked your post in {title}'**
  String likedYourPostIn(String title);

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'linked to your post from {title}'**
  String linkedToYourPostFrom(String title);

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'sent you {title}'**
  String sentYou(String title);

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'invited you to {title}'**
  String invitedYouToNotificationtypes(String title);

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'accepted your invitation'**
  String get acceptedYourInvitation;

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'posted in {title}'**
  String postedIn(String title);

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You earned the {badge} badge'**
  String youEarnedTheBadge(String badge);

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You earned a badge'**
  String get youEarnedABadge;

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{countLabelCountMessage} in your {group} inbox'**
  String inYourInbox(String countLabelCountMessage, String group);

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You\'\'re now a member of {group}'**
  String youReNowAMemberOf(String group);

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'membership request'**
  String get membershipRequest;

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reminder: {reminderTitleNotification}'**
  String reminderNotificationtypes(String reminderTitleNotification);

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Your post in {title} was approved'**
  String yourPostInWasApproved(String title);

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'New features are available'**
  String get newFeaturesAreAvailable;

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'There is new advice on your site dashboard'**
  String get thereIsNewAdviceOnYourSiteDashboard;

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Upcoming changes were automatically enabled'**
  String get upcomingChangesWereAutomaticallyEnabled;

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Upcoming changes are available for preview'**
  String get upcomingChangesAreAvailableForPreview;

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'\'\'{namesFirst}\'\' has been automatically enabled'**
  String hasBeenAutomaticallyEnabled(String namesFirst);

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'\'\'{namesFirst}\'\' is available for preview'**
  String isAvailableForPreview(String namesFirst);

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'\'\'{names}\'\' and \'\'{namesValue2}\'\' were automatically enabled'**
  String andWereAutomaticallyEnabled(String names, String namesValue2);

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'\'\'{names}\'\' and \'\'{namesValue2}\'\' are available for preview'**
  String andAreAvailableForPreview(String names, String namesValue2);

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'\'\'{namesFirst}\'\' and {otherCount} more changes were automatically enabled'**
  String andMoreChangesWereAutomaticallyEnabled(
    String namesFirst,
    String otherCount,
  );

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'\'\'{namesFirst}\'\' and {otherCount} more changes are available for preview'**
  String andMoreChangesAreAvailableForPreview(
    String namesFirst,
    String otherCount,
  );

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'one of your posts'**
  String get oneOfYourPosts;

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{count} of your posts'**
  String ofYourPosts(String count);

  /// English UI message used by models/user_directory.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Directory column is missing its name.'**
  String get directoryColumnIsMissingItsName;

  /// English UI message used by models/user_directory.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Replies posted'**
  String get repliesPosted;

  /// English UI message used by models/user_directory.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Directory user is missing a username.'**
  String get directoryUserIsMissingAUsername;

  /// English UI message used by models/user_flair.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Group flair'**
  String get groupFlair;

  /// English UI message used by models/discourse_instance.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get community;

  /// English UI message used by models/discourse_instance.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get admin;

  /// English UI message used by models/group_route.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid group directory route'**
  String get invalidGroupDirectoryRoute;

  /// English UI message used by models/group_route.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid group route name'**
  String get invalidGroupRouteName;

  /// English UI message used by models/group_route.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid group route'**
  String get invalidGroupRoute;

  /// English UI message used by models/user_draft.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Untitled draft'**
  String get untitledDraft;

  /// English UI message used by models/user_draft.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'New personal message draft'**
  String get newPersonalMessageDraft;

  /// English UI message used by models/user_draft.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'New topic draft'**
  String get newTopicDraft;

  /// English UI message used by models/user_draft.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Edit topic draft'**
  String get editTopicDraft;

  /// English UI message used by models/user_draft.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Personal message draft'**
  String get personalMessageDraft;

  /// English UI message used by models/user_draft.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reply draft'**
  String get replyDraft;

  /// English UI message used by models/post_revision.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Comparing version {previous} to {current} of {total}'**
  String comparingVersionToOf(String previous, String current, String total);

  /// English UI message used by models/forum_workspace.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid forum tab anchor'**
  String get invalidForumTabAnchor;

  /// English UI message used by models/forum_theme_preferences.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid themes.'**
  String get invalidThemes;

  /// English UI message used by models/forum_theme_preferences.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'My theme {copy}'**
  String myThemeForumthemepreferences(String copy);

  /// English UI message used by models/forum_font.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get systemDefault;

  /// English UI message used by models/forum_font.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Open Sans'**
  String get openSans;

  /// English UI message used by models/forum_font.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Lato'**
  String get lato;

  /// English UI message used by models/forum_font.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'JetBrains Mono'**
  String get jetBrainsMono;

  /// English UI message used by models/forum_theme.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid theme.'**
  String get invalidTheme;

  /// English UI message used by models/forum_theme.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid {key} color.'**
  String invalidColor(String key);

  /// English UI message used by models/forum_theme.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid {key} option.'**
  String invalidOption(String key);

  /// English UI message used by models/forum_theme.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid tint.'**
  String get invalidTint;

  /// English UI message used by models/forum_theme.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid alternate palette.'**
  String get invalidAlternatePalette;

  /// English UI message used by models/forum_theme.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Duplicate palette mode.'**
  String get duplicatePaletteMode;

  /// English UI message used by models/invite.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pending;

  /// English UI message used by models/invite.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No pending invites.'**
  String get noPendingInvites;

  /// English UI message used by models/invite.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No expired invites.'**
  String get noExpiredInvites;

  /// English UI message used by models/invite.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Redeemed'**
  String get redeemed;

  /// English UI message used by models/invite.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No redeemed invites yet.'**
  String get noRedeemedInvitesYet;

  /// English UI message used by models/invite.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invite link'**
  String get inviteLink;

  /// English UI message used by models/incoming_topics.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{countsBumps, select, true{IncomingTopicsFilter.latest(categoryId: {categoryId}, tagIds: {tagIds})} other{IncomingTopicsFilter.created(categoryId: {categoryId}, tagIds: {tagIds})}}'**
  String incomingTopicsFilterCategoryIdTagIds(
    String countsBumps,
    String categoryId,
    String tagIds,
  );

  /// English UI message used by models/site_config.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'String'**
  String get string;

  /// English UI message used by models/composer_upload.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'ComposerUploadSizeLimit({maxBytes}, enforced: {enforced})'**
  String composerUploadSizeLimitEnforced(String maxBytes, String enforced);

  /// English UI message used by models/composer_upload.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{filename} is too large to upload.'**
  String isTooLargeToUpload(String filename);

  /// English UI message used by models/composer_upload.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{filename} is too large (maximum size is {humanFileSizeMaxBytes}).'**
  String isTooLargeMaximumSizeIs(String filename, String humanFileSizeMaxBytes);

  /// English UI message used by models/composer_upload.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Too many uploads. Please wait and retry.'**
  String get tooManyUploadsPleaseWaitAndRetry;

  /// English UI message used by models/composer_upload.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Too many uploads. Try again in {countLabelSecondsSecond}.'**
  String tooManyUploadsTryAgainIn(String countLabelSecondsSecond);

  /// English UI message used by models/composer_upload.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'ComposerUploadException({statusCode}, {message})'**
  String composerUploadException(String statusCode, String message);

  /// English UI message used by models/topic.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Tags are not allowed here.'**
  String get tagsAreNotAllowedHere;

  /// English UI message used by models/bookmark_reminder.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'In 2 hours'**
  String get in2Hours;

  /// English UI message used by models/bookmark_reminder.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'In 3 days'**
  String get in3Days;

  /// English UI message used by models/bookmark_reminder.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Later today'**
  String get laterToday;

  /// English UI message used by models/bookmark_reminder.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Later this week'**
  String get laterThisWeek;

  /// English UI message used by models/bookmark_reminder.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This weekend'**
  String get thisWeekend;

  /// English UI message used by models/bookmark_reminder.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Next Monday'**
  String get nextMonday;

  /// English UI message used by models/bookmark_reminder.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Monday'**
  String get monday;

  /// English UI message used by models/content_route.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get sent;

  /// English UI message used by models/content_route.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Badge'**
  String get badge;

  /// English UI message used by models/content_route.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'New - topics'**
  String get newTopicsContentroute;

  /// English UI message used by models/content_route.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'New - replies'**
  String get newRepliesContentroute;

  /// English UI message used by models/content_route.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Top - {modeTopPeriodLabel}'**
  String topContentroute(String modeTopPeriodLabel);

  /// English UI message used by models/content_route.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid content route'**
  String get invalidContentRoute;

  /// English UI message used by models/content_route.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid content route topic id'**
  String get invalidContentRouteTopicId;

  /// English UI message used by models/content_route.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid content route post number'**
  String get invalidContentRoutePostNumber;

  /// English UI message used by models/content_route.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid content route feed path'**
  String get invalidContentRouteFeedPath;

  /// English UI message used by models/content_route.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid content route message group'**
  String get invalidContentRouteMessageGroup;

  /// English UI message used by models/content_route.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid content group route'**
  String get invalidContentGroupRoute;

  /// English UI message used by models/content_route.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid content badge route'**
  String get invalidContentBadgeRoute;

  /// English UI message used by models/do_not_disturb.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'30 minutes'**
  String get message30Minutes;

  /// English UI message used by models/do_not_disturb.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Until tomorrow'**
  String get untilTomorrow;

  /// English UI message used by models/category_sidebar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'All categories'**
  String get allCategoriesCategorysidebar;

  /// English UI message used by models/badge_route.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid badge route'**
  String get invalidBadgeRoute;

  /// English UI message used by models/site_appearance.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Missing palette color {name}'**
  String missingPaletteColor(String name);

  /// English UI message used by models/shared_appearance.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid appearance.'**
  String get invalidAppearance;

  /// English UI message used by models/topic_presentation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Keep topic tabs with the list'**
  String get keepTopicTabsWithTheList;

  /// English UI message used by models/topic_presentation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Split with the list'**
  String get splitWithTheList;

  /// English UI message used by models/forum_background.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid background.'**
  String get invalidBackground;

  /// English UI message used by models/composer_placement.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dock left'**
  String get dockLeft;

  /// English UI message used by models/composer_placement.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dock bottom'**
  String get dockBottom;

  /// English UI message used by models/composer_placement.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dock right'**
  String get dockRight;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Theme tokens'**
  String get themeTokens;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Typography'**
  String get typography;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Motion'**
  String get motion;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Spacing'**
  String get spacing;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Browse components'**
  String get browseComponents;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Discourse / ui'**
  String get discourseUi;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Components'**
  String get components;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Toggle documentation theme'**
  String get toggleDocumentationTheme;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Close styleguide'**
  String get closeStyleguide;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Search components...'**
  String get searchComponents;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Component navigation'**
  String get componentNavigation;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No components match your search.'**
  String get noComponentsMatchYourSearch;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Getting started'**
  String get gettingStarted;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Previous component'**
  String get previousComponent;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Next component'**
  String get nextComponent;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Viewport width'**
  String get viewportWidth;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'360 px'**
  String get message360Px;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'768 px'**
  String get message768Px;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'1024 px'**
  String get message1024Px;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Preview settings'**
  String get previewSettings;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reset examples'**
  String get resetExamples;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Text scale'**
  String get textScale;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Right to left'**
  String get rightToLeft;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Reduce motion'**
  String get reduceMotion;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'On This Page'**
  String get onThisPage;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Hide code'**
  String get hideCode;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'View code'**
  String get viewCode;

  /// English UI message used by theme/d_icon_sets.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Lucide'**
  String get lucide;

  /// English UI message used by theme/d_icon_sets.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Phosphor'**
  String get phosphor;

  /// English UI message used by theme/d_icon_sets.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Tabler'**
  String get tabler;

  /// English UI message used by diagnostics/diagnostics_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'in-process Dart HTTP'**
  String get inProcessDartHTTP;

  /// English UI message used by diagnostics/diagnostics_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Flutter framework errors'**
  String get flutterFrameworkErrors;

  /// English UI message used by diagnostics/diagnostics_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'root-isolate platform errors'**
  String get rootIsolatePlatformErrors;

  /// English UI message used by diagnostics/diagnostics_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'reported operational errors'**
  String get reportedOperationalErrors;

  /// English UI message used by diagnostics/diagnostics_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'reported structured application logs'**
  String get reportedStructuredApplicationLogs;

  /// English UI message used by diagnostics/diagnostics_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'external browser and web-auth traffic'**
  String get externalBrowserAndWebAuthTraffic;

  /// English UI message used by diagnostics/diagnostics_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'native-plugin-internal networking'**
  String get nativePluginInternalNetworking;

  /// English UI message used by diagnostics/diagnostics_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'spawned isolates without the HTTP override'**
  String get spawnedIsolatesWithoutTheHTTPOverride;

  /// English UI message used by diagnostics/diagnostics_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'native process crashes'**
  String get nativeProcessCrashes;

  /// English UI message used by diagnostics/diagnostics_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics persistence is unavailable; history is memory-only. {safeErrorMessageError}'**
  String diagnosticsPersistenceIsUnavailableHistoryIsMemoryOnly(
    String safeErrorMessageError,
  );

  /// English UI message used by diagnostics/topic_scroll_capture.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'topic scroll and metrics notifications'**
  String get topicScrollAndMetricsNotifications;

  /// English UI message used by diagnostics/topic_scroll_capture.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'SuperListView sliver layout and visible ranges'**
  String get superListViewSliverLayoutAndVisibleRanges;

  /// English UI message used by diagnostics/topic_scroll_capture.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'visible post geometry and row attachment lifecycle'**
  String get visiblePostGeometryAndRowAttachmentLifecycle;

  /// English UI message used by diagnostics/topic_scroll_capture.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'topic window, paging, and extent invalidation decisions'**
  String get topicWindowPagingAndExtentInvalidationDecisions;

  /// English UI message used by diagnostics/topic_scroll_capture.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'viewport anchor capture and correction decisions'**
  String get viewportAnchorCaptureAndCorrectionDecisions;

  /// English UI message used by diagnostics/topic_scroll_capture.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Flutter UI-thread build and raster frame timings'**
  String get flutterUIThreadBuildAndRasterFrameTimings;

  /// English UI message used by diagnostics/topic_scroll_capture.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'post layout and viewport bookkeeping durations'**
  String get postLayoutAndViewportBookkeepingDurations;

  /// English UI message used by diagnostics/topic_scroll_capture.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'topic-list row subtree build and layout durations'**
  String get topicListRowSubtreeBuildAndLayoutDurations;

  /// English UI message used by diagnostics/topic_scroll_capture.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'sampled CPU functions in slow topic frames when available'**
  String get sampledCPUFunctionsInSlowTopicFramesWhenAvailable;

  /// English UI message used by diagnostics/topic_scroll_capture.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'recorded rendering phases in slow topic raster frames when available'**
  String get recordedRenderingPhasesInSlowTopicRasterFramesWhenAvailable;

  /// English UI message used by diagnostics/topic_scroll_capture.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'post bodies and titles'**
  String get postBodiesAndTitles;

  /// English UI message used by diagnostics/topic_scroll_capture.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'site URLs and credentials'**
  String get siteURLsAndCredentials;

  /// English UI message used by diagnostics/topic_scroll_capture.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'native compositor and operating-system traces'**
  String get nativeCompositorAndOperatingSystemTraces;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic scrolling performance report (v{reportVersion})'**
  String topicScrollingPerformanceReportV(String reportVersion);

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{appVersion, select, true{App: local build | {appBuildChannel} | {appBuildMode} | {appPlatform}} other{App: {appVersionValue5} | {appBuildChannel} | {appBuildMode} | {appPlatform}}}'**
  String app(
    String appVersion,
    String appBuildChannel,
    String appBuildMode,
    String appPlatform,
    String appVersionValue5,
  );

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Recorded: {startedAtUtcNoCapture} | {captureDurationUsToStringAsFixed}s | {captureStatus} ({stopReasonInProgress})'**
  String recordedS(
    String startedAtUtcNoCapture,
    String captureDurationUsToStringAsFixed,
    String captureStatus,
    String stopReasonInProgress,
  );

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Display at start: {summaryDisplayRefreshRate} Hz | frame budget {msAnalysisFrameBudgetUs} ms'**
  String displayAtStartHzFrameBudgetMs(
    String summaryDisplayRefreshRate,
    String msAnalysisFrameBudgetUs,
  );

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Events: {summaryEventCount} | sampled frames: {allFramesCount} | frames with topic activity: {topicFramesCount}'**
  String eventsSampledFramesFramesWithTopicActivity(
    String summaryEventCount,
    String allFramesCount,
    String topicFramesCount,
  );

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Accessibility: {enabledAccessibilityFrameworkEnabledAtSt} at start, {enabledAccessibilityFrameworkEnabledAtEn} at end | platform request {enabledAccessibilityPlatformEnabledAtSta} | {accessibilityStateChanges} state changes'**
  String accessibilityAtStartAtEndPlatformRequestStateChanges(
    String enabledAccessibilityFrameworkEnabledAtSt,
    String enabledAccessibilityFrameworkEnabledAtEn,
    String enabledAccessibilityPlatformEnabledAtSta,
    String accessibilityStateChanges,
  );

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Debug build: repeat in a profile or release build to assess the scrolling performance users experience.'**
  String get debugBuildRepeatInAProfileOrReleaseBuildToAssess;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The event limit ended this capture early. Reproduce with a shorter capture if the slow moment was missed.'**
  String get theEventLimitEndedThisCaptureEarlyReproduceWithAShorter;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No context was recorded. Start in the affected screen and scroll before stopping.'**
  String get noContextWasRecordedStartInTheAffectedScreenAndScroll;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No frame timings were delivered. Scroll for several seconds and wait a second before stopping.'**
  String get noFrameTimingsWereDeliveredScrollForSeveralSecondsAndWait;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Frames with scroll activity:'**
  String get framesWithScrollActivity;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'All sampled app frames (no topic frame matches):'**
  String get allSampledAppFramesNoTopicFrameMatches;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Over budget: {measuredOverBudget}/{measuredCount} ({measuredCountToStringAsFixed}%) | UI: {measuredSlowBuilds} | raster: {measuredSlowRasters}'**
  String overBudgetUIRaster(
    String measuredOverBudget,
    String measuredCount,
    String measuredCountToStringAsFixed,
    String measuredSlowBuilds,
    String measuredSlowRasters,
  );

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Raster: {mapMeasuredRasterUs}'**
  String raster(String mapMeasuredRasterUs);

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Vsync delay: {mapMeasuredVsyncOverheadUs}'**
  String vsyncDelay(String mapMeasuredVsyncOverheadUs);

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Total frame latency: {mapMeasuredTotalSpanUs}'**
  String totalFrameLatency(String mapMeasuredTotalSpanUs);

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Viewport bookkeeping: {mapAnalysisViewportWorkUs}'**
  String viewportBookkeeping(String mapAnalysisViewportWorkUs);

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Post row layout: {mapAnalysisPostLayoutUs}'**
  String postRowLayout(String mapAnalysisPostLayoutUs);

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic-list scroll bookkeeping: {mapAnalysisTopicListScrollWorkUs}'**
  String topicListScrollBookkeeping(String mapAnalysisTopicListScrollWorkUs);

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic-list row build: {mapAnalysisTopicListRowBuildUs}'**
  String topicListRowBuild(String mapAnalysisTopicListRowBuildUs);

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic-list row layout: {mapAnalysisTopicListRowLayoutUs}'**
  String topicListRowLayout(String mapAnalysisTopicListRowLayoutUs);

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic list: {listTopicCount} loaded topics | inbox {listInbox} | viewport extent {listViewportExtent}'**
  String topicListLoadedTopicsInboxViewportExtent(
    String listTopicCount,
    String listInbox,
    String listViewportExtent,
  );

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Users directory: {usersRowCount} loaded users | {usersColumnCount} columns | viewport extent {usersViewportExtent}'**
  String usersDirectoryLoadedUsersColumnsViewportExtent(
    String usersRowCount,
    String usersColumnCount,
    String usersViewportExtent,
  );

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Users metric maxima: {mapAnalysisUsersMaximaWorkUs}'**
  String usersMetricMaxima(String mapAnalysisUsersMaximaWorkUs);

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Topic {topicTopicId}: {topicLoadedPostCount} loaded / {topicStreamPostCount} posts | viewport {topicViewportLogicalSizeWidth} × {topicViewportLogicalSizeHeight} | pixel ratio {topicDevicePixelRatio}'**
  String topicLoadedPostsViewportPixelRatio(
    String topicTopicId,
    String topicLoadedPostCount,
    String topicStreamPostCount,
    String topicViewportLogicalSizeWidth,
    String topicViewportLogicalSizeHeight,
    String topicDevicePixelRatio,
  );

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Most expensive post layouts (up to 8, by worst layout):'**
  String get mostExpensivePostLayoutsUpTo8ByWorstLayout;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'  Topic {postTopicId}, post id {postPostId}, {postHtmlCharacters} HTML characters: {mapPostLayoutUs}'**
  String topicPostIdHTMLCharacters(
    String postTopicId,
    String postPostId,
    String postHtmlCharacters,
    String mapPostLayoutUs,
  );

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Worst sampled frames (up to 5, by UI/raster duration):'**
  String get worstSampledFramesUpTo5ByUIRasterDuration;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'  Frame {frameFrameNumber}: UI {msFrameBuildUs} ms, raster {msFrameRasterUs} ms; {frameTopicActivityLimit}'**
  String frameUIMsRasterMs(
    String frameFrameNumber,
    String msFrameBuildUs,
    String msFrameRasterUs,
    String frameTopicActivityLimit,
  );

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'    Measured row layout {workPostLayout} ms; viewport {workViewportWork} ms; topic-list build {topicListRowBuild} ms, layout {topicListRowLayout} ms'**
  String measuredRowLayoutMsViewportMsTopicListBuildMsLayout(
    String workPostLayout,
    String workViewportWork,
    String topicListRowBuild,
    String topicListRowLayout,
  );

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{phasesIsEmpty, select, true{    Rendering: no named phases; {msRenderingOutsidePhaseMarkersUs} ms outside phase markers} other{    Rendering: {durationUsMsJoin}; {msRenderingOutsidePhaseMarkersUs} ms outside phase markers}}'**
  String renderingMsOutsidePhaseMarkers(
    String phasesIsEmpty,
    String msRenderingOutsidePhaseMarkersUs,
    String durationUsMsJoin,
  );

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Activity counts: {analysisActivityCountsLimit}'**
  String activityCounts(String analysisActivityCountsLimit);

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Interpretation: UI overruns point to build/layout/paint work; raster overruns point to drawing/compositing. Viewport and row timings measure those operations only; they do not cover all UI work. Activity in a slow frame is correlation, not proof of its cause.'**
  String get interpretationUIOverrunsPointToBuildLayoutPaintWorkRasterOverruns;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Timings cover frames delivered before Stop, not idle time or native compositor stalls. UI and raster overlap; their sum is not a dropped-frame count. Topic frame matches use engine frame numbers.'**
  String get timingsCoverFramesDeliveredBeforeStopNotIdleTimeOrNative;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Post contents, titles, site URLs, and credentials are excluded. The full JSON capture is available separately.'**
  String get postContentsTitlesSiteURLsAndCredentialsAreExcludedTheFull;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'CPU sampling requires a debug or profile build.'**
  String get cPUSamplingRequiresADebugOrProfileBuild;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Run Flutter with --enable-dart-profiling and capture again.'**
  String get runFlutterWithEnableDartProfilingAndCaptureAgain;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Start the app with flutter run in debug or profile mode.'**
  String get startTheAppWithFlutterRunInDebugOrProfileMode;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Stop the capture before exporting CPU samples.'**
  String get stopTheCaptureBeforeExportingCPUSamples;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No capture has been recorded.'**
  String get noCaptureHasBeenRecorded;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The Dart VM service could not supply CPU samples.'**
  String get theDartVMServiceCouldNotSupplyCPUSamples;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'CPU profile unavailable: {reason}'**
  String cPUProfileUnavailable(String reason);

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'CPU sampling: {captureSampleCount} capture samples | {slowSampleCount} in slow topic UI frames | period {msProfileSamplePeriodUs} ms'**
  String cPUSamplingCaptureSamplesInSlowTopicUIFramesPeriodMs(
    String captureSampleCount,
    String slowSampleCount,
    String msProfileSamplePeriodUs,
  );

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'No CPU samples remain for this capture. Copy soon after stopping; the VM overwrites old samples.'**
  String get noCPUSamplesRemainForThisCaptureCopySoonAfterStopping;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'CPU functions in slow topic frames (exclusive samples):'**
  String get cPUFunctionsInSlowTopicFramesExclusiveSamples;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'CPU functions across the capture (no slow-frame samples):'**
  String get cPUFunctionsAcrossTheCaptureNoSlowFrameSamples;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'CPU runtime tags: {selectedSampleCountJoin}'**
  String cPURuntimeTags(String selectedSampleCountJoin);

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Frequent sampled call paths (leaf ← callers):'**
  String get frequentSampledCallPathsLeafCallers;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'CPU samples are statistical and may be incomplete. They are not exact durations; debug compilation, assertions, and GC can appear here.'**
  String get cPUSamplesAreStatisticalAndMayBeIncompleteTheyAreNot;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Rendering timeline unavailable. Run in profile mode to record engine phases.'**
  String get renderingTimelineUnavailableRunInProfileModeToRecordEnginePhases;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Rendering timeline: no over-budget topic raster frames.'**
  String get renderingTimelineNoOverBudgetTopicRasterFrames;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Rendering timeline: {profileMatchedFrameCount}/{profileProfiledFrameCount} profiled slow raster frames matched (up to 20 of {requested}).'**
  String renderingTimelineProfiledSlowRasterFramesMatchedUpTo20Of(
    String profileMatchedFrameCount,
    String profileProfiledFrameCount,
    String requested,
  );

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Engine markers retained during capture: {intProfileStreamedEventCount}; {intProfileRetainedEventCount} including the final snapshot; {intProfileDiscardedEventCount} discarded at the capture limit.'**
  String engineMarkersRetainedDuringCaptureIncludingTheFinalSnapshotDiscardedAt(
    String intProfileStreamedEventCount,
    String intProfileRetainedEventCount,
    String intProfileDiscardedEventCount,
  );

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Live timeline collection adds diagnostic overhead during recording.'**
  String get liveTimelineCollectionAddsDiagnosticOverheadDuringRecording;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Final engine snapshot unavailable; the last event block may be missing.'**
  String get finalEngineSnapshotUnavailableTheLastEventBlockMayBeMissing;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Rendering uses the rolling VM buffer; live recording was unavailable.'**
  String get renderingUsesTheRollingVMBufferLiveRecordingWasUnavailable;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'older than the retained engine trace'**
  String get olderThanTheRetainedEngineTrace;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'newer than the retained engine trace'**
  String get newerThanTheRetainedEngineTrace;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'multiple raster threads match'**
  String get multipleRasterThreadsMatch;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'no engine frame markers were recorded'**
  String get noEngineFrameMarkersWereRecorded;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'no overlapping engine frame marker'**
  String get noOverlappingEngineFrameMarker;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'  Rendering frame {frameFrameNumber} unmatched: {reason}.'**
  String renderingFrameUnmatched(String frameFrameNumber, String reason);

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Rendering data is incomplete; the stall cannot be attributed to an engine phase.'**
  String get renderingDataIsIncompleteTheStallCannotBeAttributedToAn;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Rendering phases are recorded engine durations, not GPU execution times. Nested phases overlap; do not add them.'**
  String
  get renderingPhasesAreRecordedEngineDurationsNotGPUExecutionTimesNested;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'no samples'**
  String get noSamples;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{rankedLengthLimit} more event types in JSON'**
  String moreEventTypesInJSON(String rankedLengthLimit);

  /// English UI message used by data/discourse_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Expected a JSON list'**
  String get expectedAJSONList;

  /// English UI message used by data/discover_sites.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Missing Discover communities.'**
  String get missingDiscoverCommunities;

  /// English UI message used by data/discourse_account_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Expected a topic tracking state list'**
  String get expectedATopicTrackingStateList;

  /// English UI message used by data/discourse_account_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Bookmark notes must be 100 characters or fewer.'**
  String get bookmarkNotesMustBe100CharactersOrFewer;

  /// English UI message used by data/discourse_account_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Bookmark reminders must be in the future.'**
  String get bookmarkRemindersMustBeInTheFuture;

  /// English UI message used by data/discourse_account_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Bookmark reminders cannot be more than 10 years away.'**
  String get bookmarkRemindersCannotBeMoreThan10YearsAway;

  /// English UI message used by data/linux_preferences_store.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Preferences are not a JSON object.'**
  String get preferencesAreNotAJSONObject;

  /// English UI message used by data/linux_preferences_store.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unreadable preferences were set aside as {uriPathSegmentsLast}.'**
  String unreadablePreferencesWereSetAsideAs(String uriPathSegmentsLast);

  /// English UI message used by data/site_appearance_loader.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'SiteAppearanceLoadException({failure}, {url}, {statusCode}, {detail})'**
  String siteAppearanceLoadException(
    String failure,
    String url,
    String statusCode,
    String detail,
  );

  /// English UI message used by data/site_appearance_loader.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'authenticated appearance has no username'**
  String get authenticatedAppearanceHasNoUsername;

  /// English UI message used by data/site_appearance_loader.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'stylesheet JSON has no new_href'**
  String get stylesheetJSONHasNoNewHref;

  /// English UI message used by data/site_appearance_loader.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'redirect without a location'**
  String get redirectWithoutALocation;

  /// English UI message used by data/site_appearance_loader.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'authenticated redirect crossed origins'**
  String get authenticatedRedirectCrossedOrigins;

  /// English UI message used by data/sidebar_width_store.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not persist the sidebar width.'**
  String get couldNotPersistTheSidebarWidth;

  /// English UI message used by data/byte_cache.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Downloaded image could not be decoded.'**
  String get downloadedImageCouldNotBeDecoded;

  /// English UI message used by data/byte_cache.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Too many image redirects'**
  String get tooManyImageRedirects;

  /// English UI message used by data/byte_cache.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Timed out fetching cached bytes'**
  String get timedOutFetchingCachedBytes;

  /// English UI message used by data/emoji_picker_store.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Unsupported emoji picker preferences.'**
  String get unsupportedEmojiPickerPreferences;

  /// English UI message used by data/emoji_picker_store.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid emoji picker skin tone.'**
  String get invalidEmojiPickerSkinTone;

  /// English UI message used by data/emoji_picker_store.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid emoji picker history.'**
  String get invalidEmojiPickerHistory;

  /// English UI message used by data/emoji_picker_store.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid emoji picker context key.'**
  String get invalidEmojiPickerContextKey;

  /// English UI message used by data/emoji_picker_store.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid emoji picker context history.'**
  String get invalidEmojiPickerContextHistory;

  /// English UI message used by data/http_transport.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'HttpResponseTooLargeException({url}, {maxBytes} bytes)'**
  String httpResponseTooLargeExceptionBytes(String url, String maxBytes);

  /// English UI message used by data/http_transport.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Timed out reading response from {url}'**
  String timedOutReadingResponseFrom(String url);

  /// English UI message used by data/http_transport.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Timed out before the response body'**
  String get timedOutBeforeTheResponseBody;

  /// English UI message used by data/discourse_transport.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Expected a JSON object'**
  String get expectedAJSONObject;

  /// English UI message used by data/badges_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Missing badge'**
  String get missingBadge;

  /// English UI message used by data/discourse_request_coordinator.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Request backlog for {origin} already contains {maxQueued} operations.'**
  String requestBacklogForAlreadyContainsOperations(
    String origin,
    String maxQueued,
  );

  /// English UI message used by data/discourse_site_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'that forum address'**
  String get thatForumAddress;

  /// English UI message used by data/account_session_coordinator.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to {initialHost}.'**
  String couldNotConnectTo(String initialHost);

  /// English UI message used by data/discourse_composer_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t read {fileName}.'**
  String couldnTRead(String fileName);

  /// English UI message used by data/discourse_composer_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The site returned an incomplete upload for {fileName}.'**
  String theSiteReturnedAnIncompleteUploadFor(String fileName);

  /// English UI message used by data/discourse_composer_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load image previews.'**
  String get couldnTLoadImagePreviews;

  /// English UI message used by data/discourse_composer_api.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t upload {filename}.'**
  String couldnTUploadDiscoursecomposerapi(String filename);

  /// English UI message used by data/authenticator.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'connection superseded'**
  String get connectionSuperseded;

  /// English UI message used by data/stored_forum_base.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid stored forum base URL.'**
  String get invalidStoredForumBaseURL;

  /// English UI message used by data/diagnostics_panel_width_store.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not persist the diagnostics panel width.'**
  String get couldNotPersistTheDiagnosticsPanelWidth;

  /// English UI message used by data/site_tracker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **' (retry after {retryAfter})'**
  String retryAfter(String retryAfter);

  /// English UI message used by data/site_tracker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Message bus poll timed out'**
  String get messageBusPollTimedOut;

  /// English UI message used by data/draft_store.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid draft storage: {errorMessage}'**
  String invalidDraftStorage(String errorMessage);

  /// English UI message used by data/draft_store.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid draft storage: values must be strings'**
  String get invalidDraftStorageValuesMustBeStrings;

  /// English UI message used by data/draft_store.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid draft storage: blockers must be strings'**
  String get invalidDraftStorageBlockersMustBeStrings;

  /// English UI message used by data/draft_store.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid draft storage format'**
  String get invalidDraftStorageFormat;

  /// English UI message used by data/updater.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Stable'**
  String get stable;

  /// English UI message used by data/updater.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Canary'**
  String get canary;

  /// English UI message used by data/updater.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t reach the update server.'**
  String get couldnTReachTheUpdateServer;

  /// English UI message used by data/updater.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The update server answered with something this version does not understand.'**
  String get theUpdateServerAnsweredWithSomethingThisVersionDoesNotUnderstand;

  /// English UI message used by data/updater.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The download did not match its signature and was thrown away.'**
  String get theDownloadDidNotMatchItsSignatureAndWasThrownAway;

  /// English UI message used by data/updater.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The update downloaded but could not be installed.'**
  String get theUpdateDownloadedButCouldNotBeInstalled;

  /// English UI message used by data/updater.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'This build cannot update itself.'**
  String get thisBuildCannotUpdateItself;

  /// English UI message used by data/user_api_key.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Connection cancelled.'**
  String get connectionCancelled;

  /// English UI message used by data/user_api_key.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not open the sign-in window. Check that a web view is installed.'**
  String get couldNotOpenTheSignInWindowCheckThatAWeb;

  /// English UI message used by data/user_api_key.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'The site\'\'s reply could not be verified. Please try again.'**
  String get theSiteSReplyCouldNotBeVerifiedPleaseTryAgain;

  /// English UI message used by data/user_api_key.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'callback URL exceeds protocol limit'**
  String get callbackURLExceedsProtocolLimit;

  /// English UI message used by data/user_api_key.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'unexpected callback URL'**
  String get unexpectedCallbackURL;

  /// English UI message used by data/user_api_key.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'no payload in callback'**
  String get noPayloadInCallback;

  /// English UI message used by data/user_api_key.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'encrypted payload must contain exactly one RSA block'**
  String get encryptedPayloadMustContainExactlyOneRSABlock;

  /// English UI message used by data/user_api_key.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'nonce mismatch'**
  String get nonceMismatch;

  /// English UI message used by data/user_api_key.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'no key in payload'**
  String get noKeyInPayload;

  /// English UI message used by data/user_api_key.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'encrypted payload exceeds protocol limit'**
  String get encryptedPayloadExceedsProtocolLimit;

  /// English UI message used by data/user_api_key.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'encrypted payload exceeds one RSA block'**
  String get encryptedPayloadExceedsOneRSABlock;

  /// English UI message used by data/user_api_key.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{offsetNull, select, true{FormatException: {message}} other{FormatException: {message} at {offset}}}'**
  String formatException(String offsetNull, String message, String offset);

  /// English UI message used by data/discourse_api_contracts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{term} is not a Discourse forum, or is running a version too old to support apps.'**
  String isNotADiscourseForumOrIsRunningAVersionToo(String term);

  /// English UI message used by data/discourse_api_contracts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **', statusCode: {statusCode}'**
  String statusCode(String statusCode);

  /// English UI message used by data/discourse_api_contracts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'ApiKeyRejectedException(statusCode: 403)'**
  String get apiKeyRejectedExceptionStatusCode403;

  /// English UI message used by data/discourse_api_contracts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'That wasn\'\'t accepted.'**
  String get thatWasnTAccepted;

  /// English UI message used by data/discourse_api_contracts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Too fast — try again in {waitInSeconds}s.'**
  String tooFastTryAgainInS(String waitInSeconds);

  /// English UI message used by data/discourse_api_contracts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Too fast — try again in a moment.'**
  String get tooFastTryAgainInAMoment;

  /// English UI message used by data/discourse_api_contracts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'You can\'\'t post that here — or the connection to this site has expired.'**
  String get youCanTPostThatHereOrTheConnectionToThis;

  /// English UI message used by data/discourse_api_contracts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Someone else changed that first.'**
  String get someoneElseChangedThatFirst;

  /// English UI message used by data/discourse_api_contracts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t reach the site.'**
  String get couldnTReachTheSite;

  /// English UI message used by data/discourse_api_contracts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{notSent, select, true{WriteException({failure}, statusCode: {statusCode}, retryAfter: {retryAfter}, notSent)} other{WriteException({failure}, statusCode: {statusCode}, retryAfter: {retryAfter})}}'**
  String writeExceptionStatusCodeRetryAfter(
    String notSent,
    String failure,
    String statusCode,
    String retryAfter,
  );

  /// English UI message used by data/origin_request_gate.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Origin request gate is closed.'**
  String get originRequestGateIsClosed;

  /// English UI message used by data/origin_request_gate.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Requests to {origin} are paused for {retryAfterInSeconds}s.'**
  String requestsToArePausedForS(String origin, String retryAfterInSeconds);

  /// English UI message used by data/private_storage.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid private storage: {errorMessage}'**
  String invalidPrivateStorage(String errorMessage);

  /// English UI message used by data/private_storage.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid private storage: values must be strings'**
  String get invalidPrivateStorageValuesMustBeStrings;

  /// English UI message used by data/private_storage.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Invalid private storage format'**
  String get invalidPrivateStorageFormat;

  /// English UI message used by data/media_request_coordinator.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Media requests to {origin} are paused for {retryAfterInSeconds}s.'**
  String mediaRequestsToArePausedForS(
    String origin,
    String retryAfterInSeconds,
  );

  /// English UI message used by data/media_request_coordinator.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Media request backlog for {origin} already contains {maxQueued} operations.'**
  String mediaRequestBacklogForAlreadyContainsOperations(
    String origin,
    String maxQueued,
  );

  /// English UI message used by data/topic_presentation_store.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Could not save topic view.'**
  String get couldNotSaveTopicView;

  /// English UI message used by ui/components/d_resizable.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{vRound} pixels'**
  String pixels(String vRound);

  /// English UI message used by ui/components/d_questionnaire.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{semanticLabel}, question {valueCurrent} of {valueTotal}'**
  String questionOfDquestionnaire(
    String semanticLabel,
    String valueCurrent,
    String valueTotal,
  );

  /// English UI message used by ui/components/d_data_table.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{selectedCount} of {totalCount} row(s) selected.'**
  String ofRowSSelected(String selectedCount, String totalCount);

  /// English UI message used by ui/components/d_kbd.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **', then '**
  String get then;

  /// English UI message used by ui/components/d_kbd.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'then'**
  String get thenDkbd;

  /// English UI message used by ui/components/d_select.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{first} (+{itemsLength} more)'**
  String moreDselect(String first, String itemsLength);

  /// English UI message used by plugins/chat/chat_browse_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{unread, select, true{{unreadValue2, plural, =1{{statusNull, select, true{{appL10nNo} unread message} other{{appL10nNo} unread message · {status}}}} other{{statusNull, select, true{{appL10nNo} unread messages} other{{appL10nNo} unread messages · {status}}}}}} other{{unreadValue2, plural, =1{{statusNull, select, true{{unreadValue6} unread message} other{{unreadValue6} unread message · {status}}}} other{{statusNull, select, true{{unreadValue6} unread messages} other{{unreadValue6} unread messages · {status}}}}}}}'**
  String unreadChatbrowsechannelsview(
    String unread,
    num unreadValue2,
    String statusNull,
    String appL10nNo,
    String status,
    String unreadValue6,
  );

  /// English UI message used by plugins/chat/chat_browse_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{channelTitle} menu'**
  String menu(String channelTitle);

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'(edited)'**
  String get edited;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'staff'**
  String get staffChatmessagetile;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'bot'**
  String get bot;

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **' from {name}'**
  String from(String name);

  /// English UI message used by plugins/chat/chat_channel_list_actions.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{label} options'**
  String optionsChatchannellistactions(String label);

  /// English UI message used by plugins/chat/chat_channel_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **' message'**
  String get messageChatchannelheader;

  /// English UI message used by plugins/chat/chat_channel_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **' messages'**
  String get messagesChatchannelheader;

  /// English UI message used by plugins/chat/chat_channel_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **' thread'**
  String get threadChatchannelheader;

  /// English UI message used by plugins/chat/chat_channel_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **' threads'**
  String get threadsChatchannelheader;

  /// English UI message used by plugins/chat/chat_channel_header.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'last {nowDateTimeNow} at '**
  String lastAt(String nowDateTimeNow);

  /// English UI message used by plugins/chat/chat_shell_service.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{authorAppL10nSomeone} in {channelLabel}'**
  String messageInChatshellservice(
    String authorAppL10nSomeone,
    String channelLabel,
  );

  /// English UI message used by plugins/chat/chat_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{unreadCount, plural, =1{{unreadCount} unread message} other{{unreadCount} unread messages}}'**
  String unreadChatplugin(num unreadCount);

  /// English UI message used by plugins/chat/chat_inbox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{threadCount, plural, =1{{threadCount} unread thread} other{{threadCount} unread threads}}'**
  String unreadChatinbox(num threadCount);

  /// English UI message used by plugins/chat/chat_inbox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{channelTrackingMentionCount, plural, =1{{channelTrackingMentionCount} new mention} other{{channelTrackingMentionCount} new mentions}}'**
  String messageNewChatinbox(num channelTrackingMentionCount);

  /// English UI message used by plugins/chat/chat_my_threads_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **' in {channelTitle}'**
  String messageInChatmythreadsview(String channelTitle);

  /// English UI message used by plugins/chat/chat_my_threads_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **', unread'**
  String get unreadChatmythreadsview;

  /// English UI message used by plugins/chat/chat_channel_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} message selected} other{{count} messages selected}}'**
  String selectedChatchannelview(num count);

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{label} date'**
  String dateLocaldatecomposersheet(String label);

  /// English UI message used by plugins/local_dates/local_date_composer_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{label} time'**
  String timeLocaldatecomposersheet(String label);

  /// English UI message used by plugins/voice/voice_models.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Voice room'**
  String get voiceRoom;

  /// English UI message used by plugins/voice/voice_diagnostics_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{eventTotalDurationInMilliseconds} ms'**
  String ms(String eventTotalDurationInMilliseconds);

  /// English UI message used by plugins/voice/voice_call_widget.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{callSiteName} · {callParticipantCount} present'**
  String present(String callSiteName, String callParticipantCount);

  /// English UI message used by plugins/voice/voice_diagnostics_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{stateDroppedRecords} dropped'**
  String dropped(String stateDroppedRecords);

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'group @{assignmentAssigneeGroupName}'**
  String groupAssignmentsheetValue(String assignmentAssigneeGroupName);

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'user @{assignmentAssigneeUsername}'**
  String userAssignmentsheet(String assignmentAssigneeUsername);

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'status {status}'**
  String statusAssignmentsheetValue(String status);

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'note {note}'**
  String noteAssignmentsheet(String note);

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'· group'**
  String get groupAssignplugin;

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'assigned {who}'**
  String assignedAssignplugin(String who);

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'unassigned {who}'**
  String unassignedAssignplugin(String who);

  /// English UI message used by plugins/assign/assign_plugin.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'reassigned {who}'**
  String reassigned(String who);

  /// English UI message used by plugins/discourse_events/event_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'+{numberOfHiddenRows} more'**
  String moreEventcalendar(String numberOfHiddenRows);

  /// English UI message used by plugins/discourse_events/event_calendar_data.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'day {differenceFirstDayInDays} of {differenceFirstDayInDaysValue2}'**
  String dayOf(
    String differenceFirstDayInDays,
    String differenceFirstDayInDaysValue2,
  );

  /// English UI message used by plugins/discourse_events/event_composer.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'YYYY-MM-DD HH:mm'**
  String get yYYYMMDDHHMm;

  /// English UI message used by plugins/discourse_events/event_participants.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{rowsLength} shown'**
  String shown(String rowsLength);

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{count} going'**
  String goingEventcard(String count);

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'· {count} interested'**
  String interestedEventcard(String count);

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{count} interested'**
  String interestedEventcardValue(String count);

  /// English UI message used by plugins/discourse_events/event_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{eventTitle} cover'**
  String cover(String eventTitle);

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{pollVoters} voters'**
  String voters(String pollVoters);

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{votes, plural, =1{, {appL10nMessage1Vote}, {percentage} percent} other{, {votesValue4} votes, {percentage} percent}}'**
  String percent(
    num votes,
    String appL10nMessage1Vote,
    String percentage,
    String votesValue4,
  );

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{votes} votes'**
  String votes(String votes);

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{optionHtmlLabel}, ranked {ranksOptionId}'**
  String ranked(String optionHtmlLabel, String ranksOptionId);

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{namesFirst} or {namesLast}'**
  String or(String namesFirst, String namesLast);

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{namesLengthJoin}, or {namesLast}'**
  String orPollcard(String namesLengthJoin, String namesLast);

  /// English UI message used by shell/app_settings_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{percentage} percent'**
  String percentAppsettingspage(String percentage);

  /// English UI message used by shell/app_settings_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get orAppsettingspage;

  /// English UI message used by shell/composer_block_surface.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{blockLabel} actions'**
  String actionsComposerblocksurface(String blockLabel);

  /// English UI message used by shell/composer_list_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{itemLabel} item'**
  String item(String itemLabel);

  /// English UI message used by shell/notification_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{line}, unread'**
  String unreadNotificationlist(String line);

  /// English UI message used by shell/topic_list_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} more tag} other{{count} more tags}}'**
  String moreTopiclistview(num count);

  /// English UI message used by shell/topic_list_indicators.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} unread post} other{{count} unread posts}}'**
  String unreadTopiclistindicators(num count);

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'SMTP server'**
  String get sMTPServer;

  /// English UI message used by shell/group/group_manage_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'SSL mode'**
  String get sSLMode;

  /// English UI message used by shell/groups_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{humanizeType} groups'**
  String groupsGroupspage(String humanizeType);

  /// English UI message used by shell/topic_list_navigation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **', selected'**
  String get selectedTopiclistnavigation;

  /// English UI message used by shell/post_flag_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{postFlagTypeMaximumMessageLengthLength} remaining'**
  String remaining(String postFlagTypeMaximumMessageLengthLength);

  /// English UI message used by shell/composer_selection_colors.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{background, select, true{{appL10nBackground} color: {name}} other{{appL10nText} color: {name}}}'**
  String colorComposerselectioncolors(
    String background,
    String appL10nBackground,
    String name,
    String appL10nText,
  );

  /// English UI message used by shell/invite_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{inviteRedemptionCount} of {inviteMaxRedemptions} uses'**
  String ofUses(String inviteRedemptionCount, String inviteMaxRedemptions);

  /// English UI message used by shell/oneboxes/twitter.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Post on X'**
  String get postOnX;

  /// English UI message used by shell/oneboxes/twitter.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Quoted post'**
  String get quotedPost;

  /// English UI message used by shell/oneboxes/embedded.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{uriHost} embed'**
  String embed(String uriHost);

  /// English UI message used by shell/global_search_filters.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'pdf, png, jpg'**
  String get pdfPngJpg;

  /// English UI message used by shell/user_status.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{statusDescription} — until {contextFormatMediumDateUntil} {clockTimeLabelContextUntil}'**
  String untilUserstatus(
    String statusDescription,
    String contextFormatMediumDateUntil,
    String clockTimeLabelContextUntil,
  );

  /// English UI message used by shell/composer_recipients.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{recipientsLength} recipients'**
  String recipientsComposerrecipientsValue(String recipientsLength);

  /// English UI message used by shell/user_summary.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{badgeCount, plural, =1{{badgeName}, earned {badgeCount} time} other{{badgeName}, earned {badgeCount} times}}'**
  String earnedUsersummary(num badgeCount, String badgeName);

  /// English UI message used by shell/topic_tag_selector.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{selectedLength} tags'**
  String tagsTopictagselectorValue(String selectedLength);

  /// English UI message used by shell/time_gap.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{daysSince, plural, =1{{daysSince} day later} other{{daysSince} days later}}'**
  String later(num daysSince);

  /// English UI message used by shell/time_gap.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{months, plural, =1{{months} month later} other{{months} months later}}'**
  String laterTimegap(num months);

  /// English UI message used by shell/time_gap.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{years, plural, =1{{years} year later} other{{years} years later}}'**
  String laterTimegapValue(num years);

  /// English UI message used by shell/forum_theme_new_dialog.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{baseName} copy'**
  String copyForumthemenewdialog(String baseName);

  /// English UI message used by shell/topic_create_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'+{otherDraftCount} other {noun}'**
  String otherTopiccreatebutton(String otherDraftCount, String noun);

  /// English UI message used by shell/bookmark_ui.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{localizationsFormatMediumDateWall} at {clockTimeLabelContextWall}'**
  String at(
    String localizationsFormatMediumDateWall,
    String clockTimeLabelContextWall,
  );

  /// English UI message used by shell/instance_sidebar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{showShortcuts, select, true{{appL10nShortcutsInstancesidebar} navigation} other{{labelAppL10nForum} navigation}}'**
  String navigationInstancesidebar(
    String showShortcuts,
    String appL10nShortcutsInstancesidebar,
    String labelAppL10nForum,
  );

  /// English UI message used by shell/instance_sidebar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{sectionUnreadCount, plural, =1{, {sectionUnreadCount} unread message} other{, {sectionUnreadCount} unread messages}}'**
  String unreadInstancesidebar(num sectionUnreadCount);

  /// English UI message used by shell/post_permanent_delete.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get oK;

  /// English UI message used by shell/aggregate_branding.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'alpha'**
  String get alpha;

  /// English UI message used by shell/new_tab_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{label} at {wallUse24HourClockUse24HourClock}'**
  String atNewtabpage(String label, String wallUse24HourClockUse24HourClock);

  /// English UI message used by shell/new_tab_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'TWO PANELS'**
  String get tWOPANELS;

  /// English UI message used by shell/message_archive_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'the {group} inbox'**
  String theInbox(String group);

  /// English UI message used by shell/message_archive_button.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **' and '**
  String get and;

  /// English UI message used by shell/composer_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'one {kind}'**
  String one(String kind);

  /// English UI message used by shell/post_likes.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{count} likes'**
  String likesPostlikes(String count);

  /// English UI message used by shell/post_likes.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{postLikeCount} likes'**
  String likesPostlikesValue(String postLikeCount);

  /// English UI message used by shell/post_likes.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'and {hidden} others'**
  String andOthers(String hidden);

  /// English UI message used by shell/topic_progress.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'of {total}'**
  String messageOf(String total);

  /// English UI message used by shell/forum_appearance_settings.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Home default'**
  String get homeDefault;

  /// English UI message used by shell/post_revision_history.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{count} edits'**
  String edits(String count);

  /// English UI message used by shell/post_revision_history.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{age} ago'**
  String ago(String age);

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} post selected} other{{count} posts selected}}'**
  String selectedTopicview(num count);

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'deleted'**
  String get deletedTopicview;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'wiki'**
  String get wikiTopicview;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'locked'**
  String get locked;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'hidden'**
  String get hiddenTopicview;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'moderator'**
  String get moderatorTopicview;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{remaining, plural, =1{{remaining} more link} other{{remaining} more links}}'**
  String moreTopicview(num remaining);

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'view'**
  String get view;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'views'**
  String get viewsTopicview;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'reply'**
  String get replyTopicview;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'replies'**
  String get repliesTopicview;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'like'**
  String get likeTopicview;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'likes'**
  String get likesTopicview;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'link'**
  String get linkTopicview;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'links'**
  String get links;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'user'**
  String get userTopicview;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'users'**
  String get usersTopicview;

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String min(String minutes);

  /// English UI message used by shell/topic_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'read'**
  String get readTopicview;

  /// English UI message used by shell/small_action.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'invited {subject}'**
  String invitedSmallaction(String subject);

  /// English UI message used by shell/small_action.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'removed {subject}'**
  String removed(String subject);

  /// English UI message used by shell/update_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{bytesMbToStringAsFixed} MB'**
  String mB(String bytesMbToStringAsFixed);

  /// English UI message used by shell/update_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{bytesRound} KB'**
  String kB(String bytesRound);

  /// English UI message used by shell/reaction_presentation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{count} reactions'**
  String reactionsReactionpresentation(String count);

  /// English UI message used by shell/reaction_presentation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'1 {reaction} reaction'**
  String message1ReactionReactionpresentation(String reaction);

  /// English UI message used by shell/reaction_presentation.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{count} {reaction} reactions'**
  String reactionsReactionpresentationValue(String count, String reaction);

  /// English UI message used by shell/main_content.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{topicFeedMenuLabelMode} topics'**
  String topicsMaincontent(String topicFeedMenuLabelMode);

  /// English UI message used by shell/main_content.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{count} groups'**
  String groupsMaincontent(String count);

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{filterLabel} value'**
  String valueGlobalsearchfilterpicker(String filterLabel);

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{filterLabel} condition'**
  String condition(String filterLabel);

  /// English UI message used by shell/global_search_category_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{categoryPluralCategories} loaded'**
  String loaded(String categoryPluralCategories);

  /// English UI message used by shell/global_search_category_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{choicesLength} of {total} categories'**
  String ofCategories(String choicesLength, String total);

  /// English UI message used by shell/global_search_category_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{categoryPluralCategories} found'**
  String found(String categoryPluralCategories);

  /// English UI message used by shell/global_search_category_editor.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{selectedLength} selected'**
  String selectedGlobalsearchcategoryeditor(String selectedLength);

  /// English UI message used by shell/diagnostics_panel.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{millisecondsRound} ms'**
  String msDiagnosticspanel(String millisecondsRound);

  /// English UI message used by shell/user_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'suspended'**
  String get suspended;

  /// English UI message used by shell/user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{sectionLabel}, {sectionBadge} unread'**
  String unreadUsermenu(String sectionLabel, String sectionBadge);

  /// English UI message used by shell/user_menu.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{count} unread'**
  String unreadUsermenuValue(String count);

  /// English UI message used by shell/badges_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{numberCount} awarded'**
  String awarded(String numberCount);

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'liked {postsCount}'**
  String liked(String postsCount);

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'linked {postsCount}'**
  String linked(String postsCount);

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'created {title}'**
  String created(String title);

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'moved {title}'**
  String moved(String title);

  /// English UI message used by plugin_api/notification_types.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{countAppL10nMembershipRequest} for {group}'**
  String messageFor(String countAppL10nMembershipRequest, String group);

  /// English UI message used by models/forum_theme_presets.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Grey Amber'**
  String get greyAmber;

  /// English UI message used by models/forum_theme_presets.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Shades of Blue'**
  String get shadesOfBlue;

  /// English UI message used by models/forum_theme_presets.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Latte'**
  String get latte;

  /// English UI message used by models/forum_theme_presets.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Summer'**
  String get summer;

  /// English UI message used by models/forum_theme_presets.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dark Rose'**
  String get darkRose;

  /// English UI message used by models/forum_theme_presets.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Dracula'**
  String get dracula;

  /// English UI message used by models/forum_theme_presets.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Solarized'**
  String get solarized;

  /// English UI message used by models/forum_theme_presets.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Clover'**
  String get clover;

  /// English UI message used by models/forum_theme_presets.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Blank'**
  String get blank;

  /// English UI message used by styleguide/styleguide_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'Foundations'**
  String get foundations;

  /// English UI message used by diagnostics/diagnostics_controller.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{errorMessage} (offset {offset})'**
  String offset(String errorMessage, String offset);

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'no capture'**
  String get noCapture;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'in progress'**
  String get inProgress;

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'UI build/layout/paint: {mapMeasuredBuildUs}'**
  String uIBuildLayoutPaint(String mapMeasuredBuildUs);

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'    CPU ({cpuSampleCount} samples): {cpuFunctionsLineCpuLimit}'**
  String cPUSamples(String cpuSampleCount, String cpuFunctionsLineCpuLimit);

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{phaseName} {msPhaseDurationUs} ms'**
  String msTopicscrollreport(String phaseName, String msPhaseDurationUs);

  /// English UI message used by diagnostics/topic_scroll_report.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{statsCount} samples | p50 {msStatsP50} ms | p95 {msStatsP95} ms | p99 {msStatsP99} ms | max {msStatsMax} ms'**
  String samplesP50MsP95MsP99MsMaxMs(
    String statsCount,
    String msStatsP50,
    String msStatsP95,
    String msStatsP99,
    String msStatsMax,
  );

  /// English UI message used by plugins/prometheus_alert_receiver/alert_tables.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{collapsed, select, true{{appL10nExpand} {groupStatusLabel}: {groupHeading} ({groupAlertsLength})} other{{appL10nCollapse} {groupStatusLabel}: {groupHeading} ({groupAlertsLength})}}'**
  String messageAlerttables(
    String collapsed,
    String appL10nExpand,
    String groupStatusLabel,
    String groupHeading,
    String groupAlertsLength,
    String appL10nCollapse,
  );

  /// English UI message used by plugins/chat/chat_browse_channels_view.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{following, select, true{{appL10nLeave} {channelTitle}} other{{appL10nJoin} {channelTitle}}}'**
  String messageChatbrowsechannelsview(
    String following,
    String appL10nLeave,
    String channelTitle,
    String appL10nJoin,
  );

  /// English UI message used by plugins/chat/chat_message_tile.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{participants, plural, =1{ {participants} participant.} other{ {participants} participants.}}'**
  String messageChatmessagetile(num participants);

  /// English UI message used by plugins/chat/chat_inbox.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} message} other{{count} messages}}'**
  String messageChatinbox(num count);

  /// English UI message used by plugins/assign/assignment_sheet.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{assigneeIsGroup, select, true{{assigneeDisplayName}, group @{assigneeIdentifier}} other{{assigneeDisplayName}, user @{assigneeIdentifier}}}'**
  String messageAssignmentsheet(
    String assigneeIsGroup,
    String assigneeDisplayName,
    String assigneeIdentifier,
  );

  /// English UI message used by plugins/discourse_github/oneboxes/github.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{additions, plural, =1{{deletions, plural, =1{{additions} addition, {deletions} deletion} other{{additions} addition, {deletions} deletions}}} other{{deletions, plural, =1{{additions} additions, {deletions} deletion} other{{additions} additions, {deletions} deletions}}}}'**
  String messageGithub(num additions, num deletions);

  /// English UI message used by plugins/discourse_events/event_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{direction, select, true{{schedule, select, true{{appL10nPrevious} month} other{{appL10nPrevious} {viewName}}}} other{{schedule, select, true{{appL10nNext} month} other{{appL10nNext} {viewName}}}}}'**
  String messageEventcalendar(
    String direction,
    String schedule,
    String appL10nPrevious,
    String viewName,
    String appL10nNext,
  );

  /// English UI message used by plugins/discourse_events/event_calendar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{timeline, select, true{{timeLabelEvent} } other{{timeEventLocalStart} }}'**
  String messageEventcalendarValue(
    String timeline,
    String timeLabelEvent,
    String timeEventLocalStart,
  );

  /// English UI message used by plugins/discourse_events/event_topic_title.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{allDay, select, true{{dateFormatStart} – {dateFormatEnd} · {appL10nAllDay}} other{{dateFormatStart} – {dateFormatEnd} · {days} days}}'**
  String messageEventtopictitle(
    String allDay,
    String dateFormatStart,
    String dateFormatEnd,
    String appL10nAllDay,
    String days,
  );

  /// English UI message used by plugins/discourse_events/event_topic_title.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{allDay, select, true{{dateFormatStart} · {appL10nAllDay}} other{{dateFormatStart} · {timeStart}}}'**
  String messageEventtopictitleValue(
    String allDay,
    String dateFormatStart,
    String appL10nAllDay,
    String timeStart,
  );

  /// English UI message used by plugins/discourse_events/event_time.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{endNull, select, true{{zoneNull, select, true{{dateFormatStart}, {timeStart}} other{{dateFormatStart}, {timeStart} ({zone})}}} other{{sameDay, select, true{{zoneNull, select, true{{dateFormatStart}, {timeStart} → {timeEnd}} other{{dateFormatStart}, {timeStart} → {timeEnd} ({zone})}}} other{{zoneNull, select, true{{dateFormatStart}, {timeStart} → {dateFormatEnd}, {timeEnd}} other{{dateFormatStart}, {timeStart} → {dateFormatEnd}, {timeEnd} ({zone})}}}}}}'**
  String messageEventtime(
    String endNull,
    String zoneNull,
    String dateFormatStart,
    String timeStart,
    String zone,
    String sameDay,
    String timeEnd,
    String dateFormatEnd,
  );

  /// English UI message used by plugins/poll/poll_card.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{votes, plural, =1{{appL10nMessage1Vote}, {percentage}%} other{{votesValue4} votes, {percentage}%}}'**
  String messagePollcard(
    num votes,
    String appL10nMessage1Vote,
    String percentage,
    String votesValue4,
  );

  /// English UI message used by shell/topic_move_posts.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{message, select, true{{appL10nMessageTopicmoveposts} #{destinationId}} other{{appL10nTopic} #{destinationId}}}'**
  String messageTopicmovepostsValue(
    String message,
    String appL10nMessageTopicmoveposts,
    String destinationId,
    String appL10nTopic,
  );

  /// English UI message used by shell/group_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{groupUserCount, plural, =1{{groupUserCount} member} other{{groupUserCount} members}}'**
  String messageGrouppage(num groupUserCount);

  /// English UI message used by shell/groups_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{dataTotalRows, plural, =1{{dataTotalRows} group} other{{dataTotalRows} groups}}'**
  String messageGroupspage(num dataTotalRows);

  /// English UI message used by shell/composer_upload_attachment.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{retrying, select, true{{appL10nRetrying} · {uploadProgressRound}%} other{{appL10nUploading} · {uploadProgressRound}%}}'**
  String messageComposeruploadattachment(
    String retrying,
    String appL10nRetrying,
    String uploadProgressRound,
    String appL10nUploading,
  );

  /// English UI message used by shell/invite_list.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{redeemed, select, true{{appL10nJoined} {contextFormatMediumDateDate}} other{{expired, select, true{{appL10nExpired} {contextFormatMediumDateDate}} other{{appL10nExpires} {contextFormatMediumDateDate}}}}}'**
  String messageInvitelist(
    String redeemed,
    String appL10nJoined,
    String contextFormatMediumDateDate,
    String expired,
    String appL10nExpired,
    String appL10nExpires,
  );

  /// English UI message used by shell/forum_tabs_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{badgeUrgent, select, true{{title}, {appL10nUrgentUnreadActivity}} other{{title}, {appL10nUnreadActivity}}}'**
  String messageForumtabsbar(
    String badgeUrgent,
    String title,
    String appL10nUrgentUnreadActivity,
    String appL10nUnreadActivity,
  );

  /// English UI message used by shell/forum_tabs_bar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{badgeCount, plural, =1{{title}, {badgeCount} {appL10nUnreadItem}} other{{title}, {badgeCount} {appL10nUnreadItems}}}'**
  String messageForumtabsbarValue(
    num badgeCount,
    String title,
    String appL10nUnreadItem,
    String appL10nUnreadItems,
  );

  /// English UI message used by shell/composer_image_gallery.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{imageCount, plural, =1{{imageCount} image} other{{imageCount} images}}'**
  String messageComposerimagegallery(num imageCount);

  /// English UI message used by shell/instance_sidebar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{collapsed, select, true{{appL10nExpand} {sectionTitle}{unreadDescription}} other{{appL10nCollapse} {sectionTitle}{unreadDescription}}}'**
  String messageInstancesidebar(
    String collapsed,
    String appL10nExpand,
    String sectionTitle,
    String unreadDescription,
    String appL10nCollapse,
  );

  /// English UI message used by shell/instance_sidebar.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} {appL10nUnreadItem}} other{{count} {appL10nUnreadItems}}}'**
  String messageInstancesidebarValue(
    num count,
    String appL10nUnreadItem,
    String appL10nUnreadItems,
  );

  /// English UI message used by shell/topic_category_selector.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{parentNull, select, true{{appL10nCategory}: {label}} other{{appL10nSubcategoryTopiccategoryselector}: {label}}}'**
  String messageTopiccategoryselector(
    String parentNull,
    String appL10nCategory,
    String label,
    String appL10nSubcategoryTopiccategoryselector,
  );

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{saved, select, true{{appL10nSavedTags} · {choicesLength}} other{{queryIsEmpty, select, true{{appL10nAvailableTags} · {choicesLength}} other{{appL10nMatchingTags} · {choicesLength}}}}}'**
  String messageGlobalsearchfilterpicker(
    String saved,
    String appL10nSavedTags,
    String choicesLength,
    String queryIsEmpty,
    String appL10nAvailableTags,
    String appL10nMatchingTags,
  );

  /// English UI message used by shell/global_search_filter_picker.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{saved, select, true{{appL10nNoSavedTagsMatch} “{query}”} other{{appL10nNoTagsMatch} “{query}”}}'**
  String messageGlobalsearchfilterpickerValue(
    String saved,
    String appL10nNoSavedTagsMatch,
    String query,
    String appL10nNoTagsMatch,
  );

  /// English UI message used by shell/badges_page.dart. Keep placeholders intact.
  ///
  /// In en, this message translates to:
  /// **'{catalogTotal, plural, =1{{catalogHasPersonalState, select, true{{numberCatalogTotal} badge · {numberCatalogEarned} earned} other{{numberCatalogTotal} badge}}} other{{catalogHasPersonalState, select, true{{numberCatalogTotal} badges · {numberCatalogEarned} earned} other{{numberCatalogTotal} badges}}}}'**
  String messageBadgespage(
    num catalogTotal,
    String catalogHasPersonalState,
    String numberCatalogTotal,
    String numberCatalogEarned,
  );

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} badge} other{{number} badges}}'**
  String countBadge(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{badge} other{badges}}'**
  String nounBadge(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} reply} other{{number} replies}}'**
  String countReply(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{reply} other{replies}}'**
  String nounReply(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} person} other{{number} people}}'**
  String countPerson(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{person} other{people}}'**
  String nounPerson(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} click} other{{number} clicks}}'**
  String countClick(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{click} other{clicks}}'**
  String nounClick(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} like} other{{number} likes}}'**
  String countLike(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{like} other{likes}}'**
  String nounLike(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} member} other{{number} members}}'**
  String countMember(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{member} other{members}}'**
  String nounMember(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} topic} other{{number} topics}}'**
  String countTopic(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{topic} other{topics}}'**
  String nounTopic(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} post} other{{number} posts}}'**
  String countPost(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{post} other{posts}}'**
  String nounPost(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} view} other{{number} views}}'**
  String countView(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{view} other{views}}'**
  String nounView(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} message} other{{number} messages}}'**
  String countMessage(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{message} other{messages}}'**
  String nounMessage(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} reaction} other{{number} reactions}}'**
  String countReaction(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{reaction} other{reactions}}'**
  String nounReaction(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} category} other{{number} categories}}'**
  String countCategory(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{category} other{categories}}'**
  String nounCategory(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} entry} other{{number} entries}}'**
  String countEntry(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{entry} other{entries}}'**
  String nounEntry(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} day} other{{number} days}}'**
  String countDay(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{day} other{days}}'**
  String nounDay(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} tag} other{{number} tags}}'**
  String countTag(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{tag} other{tags}}'**
  String nounTag(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} second} other{{number} seconds}}'**
  String countSecond(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{second} other{seconds}}'**
  String nounSecond(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} repost} other{{number} reposts}}'**
  String countRepost(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{repost} other{reposts}}'**
  String nounRepost(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} unread notification} other{{number} unread notifications}}'**
  String countUnreadNotification(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{unread notification} other{unread notifications}}'**
  String nounUnreadNotification(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} membership request} other{{number} membership requests}}'**
  String countMembershipRequest(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{membership request} other{membership requests}}'**
  String nounMembershipRequest(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} thread} other{{number} threads}}'**
  String countThread(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{thread} other{threads}}'**
  String nounThread(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} link} other{{number} links}}'**
  String countLink(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{link} other{links}}'**
  String nounLink(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} user} other{{number} users}}'**
  String countUser(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{user} other{users}}'**
  String nounUser(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} image} other{{number} images}}'**
  String countImage(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{image} other{images}}'**
  String nounImage(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} draft} other{{number} drafts}}'**
  String countDraft(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{draft} other{drafts}}'**
  String nounDraft(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} recipient} other{{number} recipients}}'**
  String countRecipient(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{recipient} other{recipients}}'**
  String nounRecipient(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} vote} other{{number} votes}}'**
  String countVote(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{vote} other{votes}}'**
  String nounVote(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} voter} other{{number} voters}}'**
  String countVoter(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{voter} other{voters}}'**
  String nounVoter(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} group} other{{number} groups}}'**
  String countGroup(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{group} other{groups}}'**
  String nounGroup(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} minute} other{{number} minutes}}'**
  String countMinute(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{minute} other{minutes}}'**
  String nounMinute(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} hour} other{{number} hours}}'**
  String countHour(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{hour} other{hours}}'**
  String nounHour(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} month} other{{number} months}}'**
  String countMonth(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{month} other{months}}'**
  String nounMonth(num count);

  /// Complete count label, including the formatted number. Translate every plural form as a whole.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{number} year} other{{number} years}}'**
  String countYear(num count, String number);

  /// Count-dependent noun for a layout that displays the number separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{year} other{years}}'**
  String nounYear(num count);

  /// Localized namedReactions label.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 {reaction} reaction} other{{count} {reaction} reactions}}'**
  String namedReactions(num count, String reaction);

  /// Localized relativeYears label.
  ///
  /// In en, this message translates to:
  /// **'{count}y'**
  String relativeYears(int count);

  /// Localized relativeMonths label.
  ///
  /// In en, this message translates to:
  /// **'{count}mo'**
  String relativeMonths(int count);

  /// Localized relativeDays label.
  ///
  /// In en, this message translates to:
  /// **'{count}d'**
  String relativeDays(int count);

  /// Localized relativeHours label.
  ///
  /// In en, this message translates to:
  /// **'{count}h'**
  String relativeHours(int count);

  /// Localized relativeMinutes label.
  ///
  /// In en, this message translates to:
  /// **'{count}m'**
  String relativeMinutes(int count);

  /// Localized relativeDurationMonths label.
  ///
  /// In en, this message translates to:
  /// **'{count}mon'**
  String relativeDurationMonths(int count);

  /// Localized relativeNow label.
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get relativeNow;

  /// Localized durationLessThanMinuteShort label.
  ///
  /// In en, this message translates to:
  /// **'<1m'**
  String get durationLessThanMinuteShort;

  /// Localized durationLessThanMinute label.
  ///
  /// In en, this message translates to:
  /// **'less than 1 min'**
  String get durationLessThanMinute;

  /// Localized durationOneHourShort label.
  ///
  /// In en, this message translates to:
  /// **'1h'**
  String get durationOneHourShort;

  /// Localized durationOneHour label.
  ///
  /// In en, this message translates to:
  /// **'about 1 hour'**
  String get durationOneHour;

  /// Localized durationOneDayShort label.
  ///
  /// In en, this message translates to:
  /// **'1d'**
  String get durationOneDayShort;

  /// Localized durationOneDay label.
  ///
  /// In en, this message translates to:
  /// **'1 day'**
  String get durationOneDay;

  /// Localized durationMinutes label.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} min} other{{count} mins}}'**
  String durationMinutes(num count);

  /// Localized durationHours label.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{about {count} hour} other{about {count} hours}}'**
  String durationHours(num count);

  /// Localized durationDays label.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} day} other{{count} days}}'**
  String durationDays(num count);

  /// Localized durationMonths label.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} month} other{{count} months}}'**
  String durationMonths(num count);

  /// Localized durationAboutYears label.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{about {count} year} other{about {count} years}}'**
  String durationAboutYears(num count);

  /// Localized durationOverYears label.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{over {count} year} other{over {count} years}}'**
  String durationOverYears(num count);

  /// Localized durationAlmostYears label.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{almost {count} year} other{almost {count} years}}'**
  String durationAlmostYears(num count);

  /// Localized durationOverYearsShort label.
  ///
  /// In en, this message translates to:
  /// **'> {count}y'**
  String durationOverYearsShort(int count);

  /// ICU DateFormat pattern for dates in stream day separators. Localize field order and punctuation; retain valid ICU pattern symbols.
  ///
  /// In en, this message translates to:
  /// **'d MMMM y'**
  String get calendarDatePattern;

  /// Localized compactThousands label.
  ///
  /// In en, this message translates to:
  /// **'{number}k'**
  String compactThousands(String number);

  /// Localized compactMillions label.
  ///
  /// In en, this message translates to:
  /// **'{number}M'**
  String compactMillions(String number);

  /// Application label or input example.
  ///
  /// In en, this message translates to:
  /// **'HH:mm:ss'**
  String get inputTimeWithSeconds;

  /// Application label or input example.
  ///
  /// In en, this message translates to:
  /// **'HH:mm'**
  String get inputTime;

  /// Application label or input example.
  ///
  /// In en, this message translates to:
  /// **'1.weeks'**
  String get recurrenceExample;

  /// Application label or input example.
  ///
  /// In en, this message translates to:
  /// **'LLL'**
  String get dateFormatExample;

  /// Application label or input example.
  ///
  /// In en, this message translates to:
  /// **'e.g. Community lounge'**
  String get voiceRoomNameExample;

  /// Application label or input example.
  ///
  /// In en, this message translates to:
  /// **'username'**
  String get usernameLowercase;

  /// Application label or input example.
  ///
  /// In en, this message translates to:
  /// **'YYYY-MM-DD'**
  String get inputIsoDate;

  /// Application label or input example.
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get urlLabel;

  /// Application label or input example.
  ///
  /// In en, this message translates to:
  /// **'meta.discourse.org'**
  String get siteAddressExample;

  /// Application label or input example.
  ///
  /// In en, this message translates to:
  /// **'is'**
  String get searchOperatorIs;

  /// Application label or input example.
  ///
  /// In en, this message translates to:
  /// **'excludes'**
  String get searchOperatorExcludes;

  /// Application label or input example.
  ///
  /// In en, this message translates to:
  /// **'chat'**
  String get chatLowercase;

  /// Complete screen-reader calendar day label, including whether today and its event count.
  ///
  /// In en, this message translates to:
  /// **'{isToday, select, true{{count, plural, =1{{date}, Today, 1 event} other{{date}, Today, {count} events}}} other{{count, plural, =1{{date}, 1 event} other{{date}, {count} events}}}}'**
  String calendarDayEventCount(String date, String isToday, num count);

  /// Application label or input example.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{date}, 1 entry} other{{date}, {count} entries}}'**
  String calendarDayEntryCount(String date, num count);

  /// Application label or input example.
  ///
  /// In en, this message translates to:
  /// **'Threading cannot be changed for this channel.'**
  String get searchThreadingCannotBeChanged;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

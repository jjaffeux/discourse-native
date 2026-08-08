/// Measurements shared across the shell's columns.
///
/// The sidebar, main content and right sidebar each build their own header, but
/// they sit side by side: their bottom borders only line up if every one of
/// them is exactly this tall.
const double shellHeaderHeight = 52;

/// How much room the docked composer takes from the post stream.
///
/// Fixed for now. It wants to be draggable, and it wants to grow with the
/// text scale rather than showing one line at twice the size.
const double composerHeight = 220;

/// How wide the composer's completion list is drawn.
///
/// Wide enough for a username and a real name side by side, narrow enough that
/// it reads as a list attached to a word rather than as a panel of its own.
const double composerSuggestionsWidth = 320;

/// One row of it. Fixed so the list's height is known before it is built,
/// which is what keeps it from ever needing to scroll.
const double composerSuggestionRowHeight = 40;

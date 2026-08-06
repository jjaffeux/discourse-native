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

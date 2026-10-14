# Mobile user-card sheet parity

Reference: `discourse-native-mockups` at `070b91a`, `UserCard`, `UserCardHead`,
`.menu-sheet.is-end` and `.menu-sheet.is-bleed`, plus the October 14 phone capture.

Phones open the account-owned card in a Native inset bottom Sheet. It shares
the topic progress menu preset: 6px side/bottom gaps above the device safe area,
rounded 22px top/24px bottom corners, and swipe, outside, Back and Escape
dismissal. Long cards scroll below the top safe area; small swipes restore the
surface. Desktop popovers and hover previews keep their existing presentation.

The Sheet owns the optional 132px banner and 45%/84%/opaque gradient wash.
With a banner, the white 36 by 5px grab handle overlays its top with a dark edge
and shadow. Loading-to-ready changes reuse the card request and account owner.
The mobile identity uses the 64px Native avatar, 18px name, 13px handle/title,
and banner text halo. Existing status, staff and suspension meaning stays visible.

Actions use Native 34px pill buttons. Message opens a draft addressed to the
card user only when both the card guardian and current reader permit it; Chat
uses the existing plugin action and request ownership. Own cards offer Edit
profile. The biography, website/location and user-local clock precede a subtle
separator and inline Last post/Joined/Read time facts. Featured badges use the
approved Native 26px preset and tier-colored artwork, with the remaining count
shown after them. Large accessibility text stacks actions and wraps facts.

The card endpoint now retains timezone, per-recipient message permission,
and the side-loaded featured badge records in server order. Desktop API and
plugin decoding remain compatible. Focused parsing/API tests cover those fields;
widget checks cover both materials/themes, large text, card/profile action,
loading/late completion, short/complete swipes, account changes and keyboard
focus. `USER_CARD_CAPTURE_DIR` on `user_card_popover_test.dart` writes the
rendered mobile matrix using the production presentation.

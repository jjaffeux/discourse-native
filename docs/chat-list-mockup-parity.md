# Chat list, threads, channel panel and unread rows

Design reference: `discourse-native-mockups` commit
`ab471b37a455a6f038a11d5b1da2e2ae43cfa1a8` on `test-mobile-layout`, all of
it. The commit diff and the end state of `src/App.tsx` at that commit were
read; line numbers below are that file at that commit.

The mockup lists seeded chats. The app lists the account's real memberships,
tracking counts and last messages. Where the mockup seeds a value, the row
names the server field the app reads instead.

## Itemized parity checklist

### Order and grouping

| # | State | Mockup evidence | Native implementation | Verification |
| --- | --- | --- | --- | --- |
| 1 | Pending | 55775–55785: in every group, what is unread first, then the rest, each part the most recent first | | |
| 2 | Pending | 55776–55785: what is muted goes last in its group, its news and all | | |
| 3 | Pending | 55807–55822: as one list, unread and starred, unread, read and starred, read, muted | | |
| 4 | Pending | 14941–14950: your own last message leaves nothing unread | | |
| 5 | Pending | 3462–3464, 55946–55958: a group shows its unread up to 10, never fewer than 4 rows, folds only when more than one row is over, keeps the open chat, and never folds standing alone | | |
| 6 | Pending | 3493, 56019–56035: the way to the rest says what is folded, "View N unread & M read chats" or "View M read chats"; rooms keep "View N more" | | |
| 7 | Pending | Diff 24461, 25911, 33121: the Recent / Unread switch is gone | | |

### The row

| # | State | Mockup evidence | Native implementation | Verification |
| --- | --- | --- | --- | --- |
| 8 | Pending | 56426, 56485–56503: an unread row is boxed in the accent at 9%, radius 10, 2 by 4 outside and 12 inside, with no rule under it; the open row keeps its tint and leading edge | | |
| 9 | Pending | 56552–56580: name 14.5, unread 700 in strong ink, read 400 in the read-title ink, muted in muted ink | | |
| 10 | Pending | 56583–56621: after the name, a star where no Starred heading says so, a lock on a private channel, a struck bell on a muted one | | |
| 11 | Pending | 56623–56643: the unread count as a chip at the top right; a muted chat with unread shows a 7px grey dot there | | |
| 12 | Pending | 56464–56474, 56644–56661: the second line is always what was said last, 12.5 in muted ink at 400, never "N new messages" | | |
| 13 | Pending | 56407–56421, 56461–56471: the face of whoever spoke, 16px, before the line; nothing before your own turn, nor before the other person's in a conversation with them alone | | |
| 14 | Pending | 56424, 56662–56671: the time at the bottom right, 12 in muted ink, in a tail column at least 56 wide | | |
| 15 | Pending | 43787, 56511–56537: the side's row is the page's row, a 40px mark and the same edges | | |
| 16 | Pending | 43796–43846: the side's row keeps its menu under the pointer and on a held press | | |

### One list, its controls and what it leads to

| # | State | Mockup evidence | Native implementation | Verification |
| --- | --- | --- | --- | --- |
| 17 | Pending | 55709, 43787, 32874: the Chats page and chat's side draw one list component | | |
| 18 | Pending | 56387–56404, 4590–4625: the controls are the field "Find a chat" on a line of its own, then the order switch drawn as two icons named By type and Newest | | |
| 19 | Pending | 30906–30924: on the side the controls stand 4, 4, 10 in on a wide window and 10, 10, 6 on a phone | | |
| 20 | Pending | 25945–25947: the page and the side each keep their own words | | |
| 21 | Pending | Diff 4592, 33003: the Browse channels and Threads pills leave the head | | |
| 22 | Pending | 3422–3429, 55840–55856: each group under its icon and name; the first 12 under the controls, the rest 18 | | |
| 23 | Pending | 55857–55962, 55992–56006: a Threads row heads the channels, drawn as a channel's row, its count of new replies as a chip and its line "N new replies in M threads" or "Replies in the channels you are in"; boxed when something is new | | |
| 24 | Pending | 55979–55991: in the one list the Threads row stands after what is unread and starred, or after all that is unread when no thread is new | | |
| 25 | Pending | 56042–56051: a Browse channels row closes the channels, "Find and join channels you are not in" | | |
| 26 | Pending | 25553–25562: only the chats you are in are listed and counted | | |
| 27 | Pending | 55789, 55826–55829, 56013–56017, 56041: voice rooms close the same list, with the way to make one | | |

### Finding

| # | State | Mockup evidence | Native implementation | Verification |
| --- | --- | --- | --- | --- |
| 28 | Pending | 55790–55802, 55967: found by name first, then by what was said or by whom, in one Results group shown whole | | |
| 29 | Pending | 56449–56458, 56472: a found row shows the line that has the words, the words marked | | |
| 30 | Pending | 55789: rooms are found by name | | |
| 31 | Pending | 56058–56069: nothing found says "None of your chats match “words”" | | |
| 32 | Pending | 56070–56078: while finding, a Browse all channels row follows, "Channels you are not in, for “words”", carrying the words | | |

### Threads

| # | State | Mockup evidence | Native implementation | Verification |
| --- | --- | --- | --- | --- |
| 33 | Pending | 32744–32832: a thread's row is laid out as a channel's: the channel's 40px mark, where it is in 12 muted with the count at the top right, the title 14.5 at 700 or 400 in the read-title ink, the last reply by its writer's face, the time at the bottom right | | |
| 34 | Pending | 32697–32726: a thread with new replies is boxed in the unread fill, reaching 12 past the others' edge, with no rule between two boxed rows | | |
| 35 | Pending | 32630–32643: new replies first, then the most recent | | |
| 36 | Pending | Diff 32938–33106, 60146: the posters' faces and the reply count leave the row | | |
| 37 | Pending | 32629: only threads in channels you are in | | |
| 38 | Pending | 32664–32667: the channel pill opens the channel panel to pick from | | |

### The channel panel

| # | State | Mockup evidence | Native implementation | Verification |
| --- | --- | --- | --- | --- |
| 39 | Pending | 3517, 33818, 36015–36047: channels are browsed in a panel over wherever it was asked for, not on a page of their own | | |
| 40 | Pending | 56293–56376: browsing, each channel is its mark, its name at 600, "· N members" and its status when not open, a Join or Leave chip, and what it is about in full under them | | |
| 41 | Pending | 36026–36030: pressing a channel opens it and closes the panel | | |
| 42 | Pending | 56383–56403, 25964–25966: chips at the foot narrow to All, Joined or Not joined and to Open, Closed or Archived, a second press on a status clearing it; it opens on Not joined and Open | | |
| 43 | Pending | 56240–56246, 56378–56382: the field "Find a channel"; nothing found says "No channels match “words”" | | |
| 44 | Pending | 56259–56291: picking, titled Channel: All channels first, then only those you are in, the name alone, a check on the one picked | | |
| 45 | Pending | 56090–56096: a channel's mark in a list to pick from is its # in its colour on nothing | | |

### Notifications

| # | State | Mockup evidence | Native implementation | Verification |
| --- | --- | --- | --- | --- |
| 46 | Pending | 53312–53318: an unread notification's row stands in the unread fill; the row under the keyboard keeps its own | | |
| 47 | Pending | 52715–52765, 53080: no rule under a sheet's head line of chips | | |

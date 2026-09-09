# Styleguide search accessibility

Native review found that the documentation search field became the semantic parent of the whole page. Its rectangle was1280×860, and its text-field label included the application title. Native accessibility consequently exposed the search alone outside popup menus.

The baseline search now has an explicit semantic boundary. Its editable role, label and bounds stay local to the search field while navigation and actions remain siblings. The generic Input owner reproduced and corrected the same behavior in its own editor wrapper; that unmerged adoption will be reconciled separately.

Source: `f0a74785453a6cfb73d2e877e16d0e415ec66a31`, branch `codex/component-fidelity-follow-up`. All31 affected styleguide/access/Sidebar tests pass with seed909614, including desktop and mobile field bounds and labels. Root/full-profile analysis are clean. Before/after evidence is in `/private/tmp/styleguide-coordinator-semantics-before.log` and `/private/tmp/styleguide-semantics-focused-final.log`.

The refreshed isolated review app is `/private/tmp/DiscourseComponentFidelityB104-f0a74785.app`, ID `org.discourse.native.component-fidelity.b104.f0a74785`. Exact source and kernel evidence is in `/private/tmp/component-fidelity-native-provenance-f0a74785.json`; kernel SHA256 is `4d40db9421fb25e37e9f734d5b6cc98e64aa3cc1d88e5d9b61eae0354966cad8`. The local debug signature retains permitted sandbox/JIT entitlements and omits restricted development identities and push entitlements. Static signature verification and read-back checks pass. Native AX reinspection is pending the serialized desktop slot.

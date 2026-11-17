GATE: OPEN 18 (rounds used up)

This is the design-skill gate result for the synthetic Desktop Companion preview, not a compiler or functional-test failure. No waivers were installed.

The companion is an existing study workspace with sidebar navigation and editable user content. Its design uses the app's light blue tonal palette, bundled Noto Sans, Google Material icons, rounded controls, and short reduced-motion-aware transitions. There are no marketing heroes, stock photographs, shaders, invented client details, or decorative scroll scenes.

The browser review covered the pairing dialog, notes workspace, complete mistake cards, and a 390-pixel layout. An interaction fixture exercised note create/edit/search/archive/delete and mistake create/filter/resolve/delete, including rendering HTML-like user input as text. These were synthetic data checks, not a test against the user's running phone.

The first gate identified real focus-contrast and heading-order issues. Those were corrected: focus rings now use the primary color, search inputs have their own visible ring, and note headings follow the workspace heading. Card action labels identify the note they act on.

The final 18 open findings are retained below because converting the workspace into a marketing landing page would conflict with the requested app interface:

| Check | Count | Reason retained |
|---|---:|---|
| text-only / no-visual | 2 | The page displays actual editable notes, rather than photographs or a mock product image. |
| moment-none | 1 | A working companion does not need a decorative marketing moment. |
| hero-screen / section-height | 2 | The workspace scrolls with its records; it is not a viewport-sized hero. |
| one-heading | 1 | Each user note has its own accessible heading. |
| container-edges | 7 | The sidebar, skip link, toolbar and individual note cards intentionally have different structural edges. |
| row-lines / row-gap | 2 | Notes vary in length and the last row can be incomplete, as in Keep. |
| button-styles | 2 | Selected navigation, secondary actions and primary creation actions have distinct semantic treatments. |
| container | 1 | This app uses a sidebar workspace, not the skill's marketing `.wrap` layout. |

The gate also retained nine non-blocking warnings about short interface copy, user-content headings, button copy, toolbar controls, and action placement. No Lighthouse/performance score is claimed. Bundled fonts and icons remove external font dependencies. The initial sandboxed screenshot attempt timed out; the skill's headless browser succeeded outside the sandbox using a dedicated project-local profile.

The rendered preview artifacts from CI contain the production template and actual bundled icon mappings; local browser interaction fixtures use synthetic notes and mistakes. Real-device LAN pairing, Android lock-screen behavior and audio need device verification.

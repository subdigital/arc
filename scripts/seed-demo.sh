#!/bin/sh
# Fills a scratch database with sample data for trying the app.
# Usage: ARC_DB_PATH=/tmp/arc-demo/arc.sqlite scripts/seed-demo.sh [path-to-arc]
set -eu
ARC="${1:-$(dirname "$0")/../.build/debug/arc}"
: "${ARC_DB_PATH:?set ARC_DB_PATH to a scratch database}"

"$ARC" project create Website --description "Marketing site" >/dev/null
"$ARC" project create API >/dev/null
"$ARC" project create Mobile >/dev/null

"$ARC" create --project Website --kind epic --title "Launch the new site" --status in_progress >/dev/null      # 1
"$ARC" create --project Website --title "Build footer" --priority high --status in_progress --epic ARC-1 --description "Footer needs:

- [x] Links
- [ ] Newsletter signup
- [ ] Legal copy

See ARC-3 for the hero. Code sample:

\`\`\`swift
struct Footer: View {
    var body: some View { Text(\"© 2026\") }
}
\`\`\`" >/dev/null                                                                                                  # 2
"$ARC" create --project Website --title "Hero image" --priority medium --epic ARC-1 >/dev/null                     # 3
"$ARC" create --parent ARC-2 --title "Add tests" >/dev/null                                                        # 4
"$ARC" create --parent ARC-2 --title "Check accessibility" --status done >/dev/null                                # 5
"$ARC" create --project Website --title "Write launch copy" --priority urgent --status in_review >/dev/null       # 6
"$ARC" create --project Website --title "Pick a typeface" --status backlog >/dev/null                             # 7
"$ARC" create --project Website --title "Old banner" --status done --epic ARC-1 >/dev/null                        # 8
"$ARC" create --project Website --title "Cancelled idea" --status canceled >/dev/null                             # 9
"$ARC" create --project API --kind epic --title "OAuth support" >/dev/null                                        # 10
"$ARC" create --project API --title "Add OAuth" --priority urgent --epic ARC-10 >/dev/null                        # 11
"$ARC" create --project API --title "Rate limiting" --priority low --status todo >/dev/null                       # 12
"$ARC" create --project Mobile --title "Crash on launch" --priority high >/dev/null                               # 13
"$ARC" comment ARC-2 "Started on the layout. Blocked by ARC-3 for the hero image." >/dev/null

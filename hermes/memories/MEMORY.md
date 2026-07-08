Homelab: R720 TrueNAS .100, RTX 4060 desktop .11, Optiplex Dell1 .11 (Dockge, runs this Hermes container among others), Optiplex hermes .12.
§
Joseph is comfortable with homelab/Docker/Dockge administration.
§
Campground finder skill: ~/.hermes/skills/campground-finder/ — 49 campground IDs near Beaverton. Script: scripts/campground_finder.py. Tent-camping only (filters RV/equestrian/group/yurt). Output: names are markdown links [Name](url), site type labels (tent-only)/(standard), no price (API unreliable). API: URL-encode start_date, 1st of month required, 429 rate limit with backoff, stderr for progress. Reference: references/recreation-gov-api.md.
§
Dashboard at dashboards/flight-tracker/index.html
§
Workspace structure: all dashboards/tools live under /workspace/dashboards/ (flight-tracker, goodwill-minipc-scanner, minipc-search, generate-index.sh, index.html). Root /workspace/ only has dashboards/ and web/.
§
Dashboard index generator skill regenerates /workspace/dashboards/index.html from subfolders.
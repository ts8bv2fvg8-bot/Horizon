# Church app research

What the leading church apps do, how the ones that work with Planning Center integrate it,
and which features this app adopts within your required scope.

## The leading apps

| App | Positioning | Features worth borrowing | Planning Center integration |
| --- | --- | --- | --- |
| **Church Center** (Planning Center) | Free with PCO. A "container" app: members pick their church inside one shared app; no church-branded App Store listing. | Native groups (chat, events, attendance), registrations, check-ins with QR station scan, giving with Apple Pay, forms, Publishing sermons. Custom pages, video and sermon notes need the paid Publishing plan. | Native. Uses Planning Center's internal APIs, so it can write registrations, check-ins and attendance. Third parties can't. |
| **Subsplash** | Custom-branded app, website and media platform for media-heavy churches | Media library with series art and offline downloads, live stream with chat, push notifications with segments, home "builder" with dynamic cards, Bible and reading plans, sermon notes | One-way sync of Subsplash Giving into PCO People and Giving. Setup needs a PCO user with full admin rights. Groups and registrations are usually links to Church Center. |
| **Pushpay** | Giving-first, large and multisite churches | Fast-give flow, recurring prompts, campus-aware content, personalized home | Two-way profile sync with PCO People, one-way donation sync into PCO Giving |
| **Tithely** | Value and small churches; free tier | Simple giving, events, media, Bible | Giving sync to its own ChMS; PCO needs a separate integration |
| **Gloo / custom builders** | Engagement platforms and white-label builders | Growth tracks and next steps, journeys, texting | Mostly through Zapier, webhooks or Church Center links |
| **Rock RMS** (ChMS, not an app) | Self-hosted ChMS | — | "Planning Center Sync v2" plugin (9 Embers, about $300/yr) syncs people; a separate recipe records PCO Giving donations in Rock |

### How third-party apps integrate Planning Center in practice

Across every vendor the pattern is the same, and this app copies it:

1. **One server-side, admin-level connection** to Planning Center, made once by a church
   admin. Subsplash requires "full admin rights". Member devices never hold admin tokens.
2. **Sync where the API allows writes**: People (profiles), Giving (recording donations
   processed elsewhere), Services (serving responses and blockouts), Groups memberships.
3. **Embed or link Church Center wherever the API is read-only.** Registrations, check-ins
   and group attendance have no public write API, so every third-party app opens Church
   Center for those steps. PCO's own comparison page makes this point when contrasting
   Church Center with custom apps.

The difference in this app is that the native layer **around** those Church Center steps is
richer: arrival detection before check-in, security codes afterwards, a leader dashboard
around attendance, and a merged events list around registration.

## Features adopted

| Feature (common to the best apps) | Where |
| --- | --- |
| Personalized home: greeting, "you're serving next", check-in banner when it matters | Home |
| Latest message with background audio and lock-screen controls; searchable archive | Home → Messages |
| Quick actions (Check In, Give, Plan a Visit, Prayer) | Home |
| Website content as the primary home feed (hero, announcements, About/Kids/Youth pages) | Home |
| Group finder with filters, map and privacy-aware locations; "help me find a group" fallback | Groups |
| Leader tools: roster, attendance status, one-tap attendance | Groups → My Groups |
| Events grouped by month, search, "registration open" filter, add to calendar, my registrations | Events |
| Frictionless giving, history, recurring gifts | Giving |
| Discipleship pathway with progress | Next Steps |
| Volunteer self-service: accept/decline, blockouts, frequency preferences | Serving (from Home, Next Steps and Profile) |
| Geofenced arrival reminder for check-in | Check-In |
| Remote configuration so staff change content without app updates | `/v1/config` |
| Accessibility labels, Dynamic Type, dark mode | Throughout |

### Recommended next phase

These are common in top apps and outside the scope you set:

- **Push notifications** (APNs + segments such as parents, volunteers, group leaders), sent
  from a small admin page or PCO People lists. This is the most-used feature in Subsplash
  and Pushpay apps.
- **Live stream** tab once Publishing "Watch Live" is enabled on channel 6131.
- **Sermon notes** (Publishing plan) and offline audio downloads.
- **Home-screen widget** for "Next serving date" and "Check-in is open".
- **Spanish localization** for Horizon Español and Esperanza.

## Sources

- Planning Center: [Church Center](https://www.planningcenter.com/church-center),
  [Church Center vs custom church apps](https://www.planningcenter.com/compare-church-center-vs-custom-church-apps),
  [Planning Center vs Subsplash](https://www.planningcenter.com/compare-planning-center-vs-subsplash),
  [Integrations](https://www.planningcenter.com/integrations),
  [Subsplash integration listing](https://www.planningcenter.com/integrations/subsplash),
  [Authentication docs](https://api.planningcenteronline.com/docs/overview/authentication),
  [Developers repo](https://github.com/planningcenter/developers) (Giving integration guide),
  issues [#911](https://github.com/planningcenter/developers/issues/911) and
  [#1263](https://github.com/planningcenter/developers/issues/1263) (Groups attendance is read-only),
  [#1503](https://github.com/planningcenter/developers/issues/1503) (Check-Ins writes not on the roadmap),
  [#1500](https://github.com/planningcenter/developers/issues/1500) (Services scheduling emails),
  [Group attendance permissions](https://www.planningcenter.com/blog/2023/03/attendance-management-focus-on-the-broader-group-by-allowing-members-to-take-attendance),
  [Permissions in Groups](https://help.planningcenter.com/en/136859-permissions-in-groups.html),
  [Manage your schedule](https://help.planningcenter.com/en/142874-manage-your-schedule.html),
  [Blockout dates](https://help.planningcenter.com/en/142872-manage-blockout-dates.html)
- Subsplash: [Planning Center integration](https://support.subsplash.com/en/articles/9021274-planning-center-integration),
  [Compare](https://www.subsplash.com/compare), [Top church apps](https://www.subsplash.com/blog/10-best-church-apps)
- Pushpay: [Best church app features](https://pushpay.com/blog/10-best-church-app-features/),
  [Integrations compared](https://pushpay.com/blog/church-software-integrations-compared/)
- Tithely: [Best church apps](https://get.tithe.ly/best/church-apps),
  [Planning Center alternative](https://get.tithe.ly/compare/planning-center-alternative)
- Rock RMS: [Planning Center Sync v2](https://www.rockrms.com/rockshop/plugin/208/planning-center-sync-v2),
  [Syncing PCO Giving into Rock](https://community.rockrms.com/recipes/521/syncing-planning-center-giving-into-rock-rms)
- Third-party reviews: [The Lead Pastor: best custom church apps](https://theleadpastor.com/tools/best-custom-church-apps/),
  [Jotform: best church apps](https://www.jotform.com/blog/best-church-apps/),
  [usecarly: Planning Center API](https://www.usecarly.com/blog/planning-center-api/)

Vendor comparison pages are marketing material. Each claim above that matters for the build
(write access, sync direction, admin requirements) was cross-checked against Planning
Center's own docs or issue tracker where possible.

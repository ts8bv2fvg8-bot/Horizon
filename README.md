# Horizon Community Church iOS app

A native SwiftUI app for [Horizon Community Church](https://www.horizoncommunity.church)
(Tualatin, OR), built on Planning Center and the church website.

**Tabs:** Home · Groups · Events · Giving · Next Steps. The profile button on every tab opens
Profile, Serving and Check-In.

| Members can… | How |
| --- | --- |
| Update their profile (name, birthday, emails, phones, address, photo) | Native, saved to PCO People |
| Set serving preferences and blockout dates | Native, saved to PCO Services |
| See serving dates and accept or decline | Native, PCO Services |
| Find a small group (search, filters, map) | Native, PCO Groups; join on Church Center in-app |
| Take small group attendance (leaders) | Native leader dashboard; submit on Church Center in-app |
| Register for events | Native list from PCO Registrations and Calendar; register on Church Center in-app |
| Give | Church Center Giving in Safari View Controller; native history from PCO Giving |
| Check in on campus | Geofenced arrival prompt and security codes natively; check in on Church Center in-app |
| Read church content | Pulled from www.horizoncommunity.church (WordPress, Squarespace or HTML, auto-detected) |
| Listen to messages | PCO Publishing podcast feed, background audio |

Read next:
- [`docs/PCO_INTEGRATION.md`](docs/PCO_INTEGRATION.md): endpoint-by-endpoint design, what PCO
  can and can't do through its API, and items to verify.
- [`docs/RESEARCH.md`](docs/RESEARCH.md): how leading church apps work and how they integrate
  Planning Center.

## Repository layout

```
ios/                 SwiftUI app (iOS 17+), generated with XcodeGen
  project.yml
  Horizon/App        Entry point, tabs, router, build config
  Horizon/Core       OAuth + PKCE, Keychain, API client, models, geofencing, audio
  Horizon/Features   Home, Groups, Events, Giving, NextSteps, Serving, Profile, CheckIn
  Horizon/Shared     Theme, loading states, Church Center web flows, HTML renderer
  HorizonTests       PKCE, decoding and profile-diff tests
backend/             Cloudflare Worker (TypeScript): Planning Center + website API for the app
  src/config.ts      Church-specific IDs (group types, forms, signups, campus, next steps)
  src/pco.ts         JSON:API client, member token verification
  src/handlers.ts    People, Services, Groups, Registrations, Calendar, Giving, Check-Ins
  src/content.ts     Website and podcast parsing
docs/
```

## Setup

### 1. Planning Center

1. **OAuth app** (member sign-in): <https://api.planningcenteronline.com/oauth/applications>.
   Redirect URI `horizonchurch://oauth/callback`, scope `people`. Copy the Client ID.
2. **Personal Access Token** for the backend: <https://api.planningcenteronline.com/personal_access_tokens>.
   Create it from a dedicated admin user with access to People, Services, Groups,
   Registrations, Check-Ins, Giving and Calendar.

### 2. Backend

```bash
cd backend
npm install
npx wrangler kv namespace create CACHE        # paste the id into wrangler.toml
npx wrangler secret put PCO_APP_ID
npx wrangler secret put PCO_SECRET
npm run typecheck && npm test
npm run deploy                                # note the *.workers.dev URL
```

For local development, put `PCO_APP_ID` and `PCO_SECRET` in `backend/.dev.vars` and run
`npm run dev`.

### 3. iOS app

```bash
brew install xcodegen
cd ios
# Edit project.yml: HORIZON_API_BASE_URL (backend URL), PCO_CLIENT_ID, DEVELOPMENT_TEAM
xcodegen
open Horizon.xcodeproj
```

Add a 1024×1024 app icon to `Horizon/Resources/Assets.xcassets/AppIcon.appiconset`, and set
`AccentColor` and `BrandNavy` to Horizon's brand colors.

## Before launch

- [ ] Confirm the endpoints in [PCO_INTEGRATION.md § Endpoints to confirm](docs/PCO_INTEGRATION.md#endpoints-to-confirm-against-the-live-api-before-launch)
      with a test volunteer, group leader and parent account.
- [ ] Confirm the website page paths in `backend/src/config.ts` (`WEBSITE_PAGES`) match
      horizoncommunity.church.
- [ ] Set the Tualatin campus coordinates (`latitude`/`longitude` in `config.ts` and
      `Campus.tualatin`) from a pin dropped on the building. The current values are
      approximate.
- [ ] Brand colors, app icon and launch screen.
- [ ] App Store privacy labels: name, email, phone, address, photos, coarse location,
      purchase history (giving history display).
- [ ] TestFlight with staff and a few volunteers.

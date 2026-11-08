# Planning Center integration

How each feature you asked for is built on Planning Center (PCO), and where PCO's API limits
it. Horizon's org data quoted here (IDs, forms, signups) was read from Planning Center
(org **61173**, Church Center subdomain **horizoncommunitychurch**) in November 2026.

## Architecture

```
 iOS app ──(1) OAuth 2.0 + PKCE──▶ api.planningcenteronline.com/oauth   (member signs in)
    │
    └──(2) HTTPS + member's access token──▶ Horizon API (backend/, Cloudflare Worker)
                                             │  verifies the token with GET /people/v2/me
                                             │  then acts with the church's admin token,
                                             │  scoped to that person id
                                             ├──▶ Planning Center API (People, Services, Groups,
                                             │     Registrations, Check-Ins, Giving, Calendar)
                                             ├──▶ www.horizoncommunity.church (content)
                                             └──▶ PCO Publishing podcast feed (sermons)

 Registration, group join, attendance, check-in, giving ──▶ Church Center pages, shown in-app
```

**Why a backend instead of calling PCO straight from the phone?**
A member's own OAuth token only carries *their* permissions. Most members have no admin
rights in People, Groups or Giving, so they can't read the group directory, edit their own
People record through the API, or see their donation history. This is the same reason
Subsplash and Pushpay ask an admin with full rights to connect Planning Center once,
server-side. The backend:

1. confirms who the member is (`GET /people/v2/me` with *their* token, so it can't be faked),
2. performs the action with the church's credential, **only on that person's records** (every
   email, phone, address, blockout or schedule id is checked against the member's own
   person before it is changed),
3. keeps the admin secret off the phone, and caches public data, which keeps the app under
   PCO's rate limit (100 requests per 20 seconds per user).

## Authentication

| Item | Value |
| --- | --- |
| Authorize | `GET https://api.planningcenteronline.com/oauth/authorize` |
| Token | `POST https://api.planningcenteronline.com/oauth/token` |
| Revoke | `POST https://api.planningcenteronline.com/oauth/revoke` |
| PKCE | Required for public clients (mobile apps), `S256` |
| Scope requested | `people`. The app only needs identity; the backend does the rest. |
| Access token | About 2 hours |
| Refresh token | Honored for 90 days; a new refresh token comes back on each refresh |
| Redirect URI | `horizonchurch://oauth/callback` |

Register the OAuth app at <https://api.planningcenteronline.com/oauth/applications>. Create
the backend's Personal Access Token at
<https://api.planningcenteronline.com/personal_access_tokens>, from an admin account with
access to People, Services, Groups, Registrations, Check-Ins, Giving and Calendar. A
dedicated "Horizon App" admin user is the safest owner for it.

## Feature map

| Requirement | Native in app | PCO endpoints (backend) | What runs on Church Center |
| --- | --- | --- | --- |
| **Update profile** | Name, nickname, birthday, emails, phones, address, photo | `GET/PATCH /people/v2/people/{id}` · `POST /people/v2/people/{id}/emails` · `PATCH/DELETE /people/v2/emails/{id}` (same for `phone_numbers`, `addresses`) · photo: `POST upload.planningcenteronline.com/v2/files`, then `PATCH person {avatar: fileId}` | Adding household members (`/me/profile-and-household`) |
| **Serving preferences** | How often per position (every week, every other week (A/B), once a month, choose weeks), max times per month or day, blockout dates | `GET/PATCH /services/v2/people/{id}/person_team_position_assignments/{id}` (`schedule_preference`, `preferred_weeks`) · `PATCH /services/v2/people/{id}` (`preferred_max_plans_per_month/day`) · `GET/POST/DELETE /services/v2/people/{id}/blockouts` | — |
| **See serving dates** | Upcoming schedule, accept or decline requests with a reason | `GET /services/v2/people/{id}/schedules` · `POST …/schedules/{id}/accept` and `/decline`, falling back to `PATCH /services/v2/service_types/{st}/plans/{p}/team_members/{pp}` with `status` C/D | — |
| **Find a small group** | Directory of the 8 Church Center–visible group types, search, day and type filters, map (approximate locations respected) | `GET /groups/v2/group_types/{id}/groups?include=location,enrollment,tags` | **Join or request to join** (group's `church_center_web_url`) |
| **Take attendance** | Leader dashboard: roster, next meetings, recent attendance and "not taken" warnings | `GET /groups/v2/people/{id}/memberships` (role = leader) · `GET /groups/v2/groups/{id}/memberships?include=person` · `GET /groups/v2/groups/{id}/events` · `GET /groups/v2/events/{id}/attendances` | **Submitting attendance** on the event page. The Groups API marks Event and Attendance read-only (developers issues #911 and #1263). |
| **Register for events** | Merged list of 22 open signups and Church Center–visible calendar events, add to calendar, "My registrations" | `GET /registrations/v2/signups?include=next_signup_time,signup_location` · `GET /calendar/v2/event_instances?filter=future&include=event` | **Registration and payment** (`new_registration_url`). The Registrations API is read-only. |
| **Give** | Giving history, year-to-date total, recurring gifts | `GET /giving/v2/people/{id}/donations?include=designations` · `GET /giving/v2/people/{id}/recurring_donations` · `GET /giving/v2/funds` | **The gift itself**, in Safari View Controller (`/giving`). |
| **Check in on campus** | Arrival detection (geofence), "check-in is open" banner (event times), household security codes | `GET /check-ins/v2/events/{id}/event_times` · `GET /check-ins/v2/people/{id}/check_ins?include=event` | **Check-in** (`/check-ins`). PCO has said a writable Check-Ins API isn't on its roadmap, for child-safety reasons (developers issue #1503). |
| **Next steps** | Pathway built from real forms and signups, with progress tracking | Config in `backend/src/config.ts` | Forms (`/people/forms/{id}`) and signups |
| **Sermons** | Latest message, archive, search, background audio with lock-screen controls | Publishing channel 6131 podcast feed | Video on Church Center channel page |

### Why giving isn't a native card form

- PCO's Giving API **records** donations that were processed somewhere else: you create a
  `PaymentSource`, a `Batch`, then `Donation`s with `Designation`s (see
  `planningcenter/developers/guides/giving_donations_integration.md`). It doesn't charge
  cards. A native form would need a separate payment processor plus syncing, which is how
  Pushpay, Tithely and Subsplash Giving work. That means a second giving platform and fees.
- App Store guideline 3.2.2 requires apps from organizations that aren't approved nonprofits
  to take donations outside the app (Safari or SMS). Opening Church Center Giving in Safari
  View Controller satisfies it. If Horizon enrolls in Apple's nonprofit program, Apple Pay
  in-app giving becomes possible (3.2.1(vi)) but would still need a processor.

### How in-app Church Center flows feel native

- `WKWebView` with the default persistent data store: members sign into Church Center once
  and stay signed in, and closing the sheet returns them to the native screen.
- The navigation delegate keeps `churchcenter.com` and `planningcenteronline.com` (plus
  Stripe and captcha domains used for payments) in-app and opens maps, phone and email
  links externally.
- Native screens show the result afterwards: the attendance count, the registration under
  "My registrations", security codes after check-in.

## Horizon's Planning Center setup (as read from your account)

- **Campuses:** Tualatin Campus (20920), 23370 SW Boones Ferry Rd, Tualatin OR 97062,
  Sundays 9:30 and 11:00. Online Campus (44469).
- **Group types visible on Church Center:** Sermon Based Small Groups, Español, Bible
  Studies, Interest Based, Sisterhood, Brotherhood, Young Adults, Singles.
- **Check-Ins events:** Horizon Kids, Esperanza Sunday Service, Middle School YTH, High
  School YTH, Young Adults (also Alpha, The Marriage Course, Kids Training).
- **Publishing:** "Weekend Service" channel 6131, with podcast feed. Watch Live isn't
  enabled.
- **Next Steps wiring:** Plan a Visit (form 10185), New Friends Brunch (signup 3998947),
  Questions About Jesus (form 10184), Water Baptism (signup 3986196), Child Dedication
  (signup 3979199), Life Group Interest (form 10180), Life Group Leader Application (form
  61155), Serve 101 (signup 3144198), Volunteer Interest (form 17164), Worship Team
  Application (form 10188), Prayer Request (form 10182), DivorceCare (signup 2148535),
  Contact Us (form 10174), Horizon Kids Registration (form 184312).
- **Giving:** the account used for this research can't read Giving data, so fund names
  weren't verified. The backend's admin token needs Giving access for giving history.

## Endpoints to confirm against the live API before launch

The official reference (api.planningcenteronline.com/docs and developer.planning.center) was
blocked by this build environment's network policy. Most endpoints above come from PCO's
public docs, its developers GitHub repo and issue tracker, and Horizon's live data. These
details need a quick check with a test account:

1. **Schedule accept/decline**: whether `POST /services/v2/people/{id}/schedules/{id}/accept`
   and `/decline` exist in the current Services version. The backend falls back to patching
   the PlanPerson `status`, which is documented.
2. **Filters**: `where[archive_status]=not_archived` (Groups), `filter=unarchived`
   (Registrations), and `filter=future` (Services schedules and blockouts). The code also
   filters on the server side, so a wrong name only costs efficiency.
3. **Church Center URLs**: `/check-ins`, `/me/profile-and-household`,
   `/registrations/reservations`, and the group event page used for attendance. Open each
   on a phone while signed in.
4. **Groups event `church_center_web_url`**: if events don't expose it, the app builds
   `{group url}/events/{id}`.

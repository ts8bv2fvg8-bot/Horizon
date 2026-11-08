// Church-specific configuration. Every ID below was read from Horizon's Planning Center
// account (org 61173) in November 2026. Staff can change these without an app release.

export const ORG = {
  name: "Horizon Community Church",
  pcoOrganizationId: "61173",
  churchCenterSubdomain: "horizoncommunitychurch",
  timeZone: "America/Los_Angeles",
  website: "https://www.horizoncommunity.church",
  churchCenter: "https://horizoncommunitychurch.churchcenter.com",
} as const;

export const CAMPUSES = [
  {
    id: "20920",
    name: "Tualatin Campus",
    street: "23370 SW Boones Ferry Rd",
    city: "Tualatin",
    state: "OR",
    zip: "97062",
    phone: "503-612-6688",
    email: "tualatin@horizoncommunity.church",
    // Approximate coordinates for the campus. Confirm on-site before launch; the app uses
    // these to offer check-in when someone arrives on campus.
    latitude: 45.3712,
    longitude: -122.7623,
    geofenceRadiusMeters: 200,
    serviceTimes: ["Sunday 9:30 AM", "Sunday 11:00 AM"],
  },
] as const;

/** Group types published on Church Center (church_center_visible = true). */
export const PUBLIC_GROUP_TYPE_IDS = [
  "57785", // Sermon Based Small Groups
  "443220", // Español
  "449208", // Bible Studies
  "449214", // Interest Based
  "449340", // Sisterhood
  "449341", // Brotherhood
  "449344", // Young Adults
  "449345", // Singles
];

/** Check-Ins events people can check into from their phone. */
export const CHECK_IN_EVENT_IDS = [
  "159391", // Horizon Kids
  "183228", // Esperanza Sunday Service
  "643907", // Middle School YTH
  "643908", // High School YTH
  "728307", // Young Adults
];

/** Publishing channel used for sermons (has a podcast feed). */
export const SERMON_CHANNEL = {
  id: "6131",
  name: "Weekend Service",
  podcastFeedUrl: "https://publishing.planningcenteronline.com/61173/podcast_feeds/6131.xml",
  churchCenterUrl: "https://horizoncommunitychurch.churchcenter.com/channels/6131",
};

const cc = (path: string) => `${ORG.churchCenter}${path}`;
const form = (id: string) => cc(`/people/forms/${id}`);
const signup = (id: string) => cc(`/registrations/events/${id}/reservations/new`);

export type NextStepAction =
  | { kind: "form"; formId: string; url: string }
  | { kind: "signup"; signupId: string; url: string }
  | { kind: "groups"; groupTypeId?: string }
  | { kind: "serve" }
  | { kind: "web"; url: string };

export interface NextStep {
  id: string;
  title: string;
  subtitle: string;
  systemImage: string; // SF Symbol name used by the iOS app
  action: NextStepAction;
}

export interface NextStepSection {
  id: string;
  title: string;
  steps: NextStep[];
}

/**
 * The "Next Steps" pathway: Know God → Find Community → Grow → Serve.
 * Every step points at a real Planning Center form or signup.
 */
export const NEXT_STEPS: NextStepSection[] = [
  {
    id: "start",
    title: "Start Here",
    steps: [
      { id: "plan-visit", title: "Plan a Visit", subtitle: "Let us know you're coming and we'll save you a seat.", systemImage: "calendar.badge.plus", action: { kind: "form", formId: "10185", url: form("10185") } },
      { id: "new-friends", title: "New Friends Brunch", subtitle: "Meet our pastors and hear the Horizon story.", systemImage: "cup.and.saucer.fill", action: { kind: "signup", signupId: "3998947", url: signup("3998947") } },
      { id: "connect-card", title: "Stay Connected", subtitle: "Get updates on what's happening at Horizon.", systemImage: "envelope.open.fill", action: { kind: "form", formId: "13035", url: form("13035") } },
    ],
  },
  {
    id: "know-god",
    title: "Know God",
    steps: [
      { id: "decision", title: "I Said Yes to Jesus", subtitle: "Tell us about your decision so we can walk with you.", systemImage: "heart.fill", action: { kind: "form", formId: "10184", url: form("10184") } },
      { id: "alpha", title: "Alpha", subtitle: "Explore life, faith and meaning over a meal.", systemImage: "questionmark.bubble.fill", action: { kind: "groups", groupTypeId: "408254" } },
      { id: "baptism", title: "Water Baptism", subtitle: "Make a public declaration of your faith.", systemImage: "drop.fill", action: { kind: "signup", signupId: "3986196", url: signup("3986196") } },
      { id: "dedication", title: "Child Dedication", subtitle: "Dedicate your child and commit to raising them in faith.", systemImage: "figure.and.child.holdinghands", action: { kind: "signup", signupId: "3979199", url: signup("3979199") } },
    ],
  },
  {
    id: "community",
    title: "Find Community",
    steps: [
      { id: "life-group", title: "Join a Life Group", subtitle: "Do life with a small group of people.", systemImage: "person.3.fill", action: { kind: "groups" } },
      { id: "life-group-interest", title: "Help Me Find a Group", subtitle: "We'll match you with a group that fits.", systemImage: "hand.raised.fill", action: { kind: "form", formId: "10180", url: form("10180") } },
      { id: "lead-group", title: "Lead a Life Group", subtitle: "Apply to host or lead a group.", systemImage: "star.fill", action: { kind: "form", formId: "61155", url: form("61155") } },
    ],
  },
  {
    id: "serve",
    title: "Serve",
    steps: [
      { id: "serve-101", title: "Serve 101", subtitle: "Discover where you fit on the team.", systemImage: "graduationcap.fill", action: { kind: "signup", signupId: "3144198", url: signup("3144198") } },
      { id: "volunteer", title: "Volunteer Interest", subtitle: "Tell us where you'd like to serve.", systemImage: "hands.sparkles.fill", action: { kind: "form", formId: "17164", url: form("17164") } },
      { id: "my-serving", title: "My Serving Schedule", subtitle: "See your dates and set your preferences.", systemImage: "calendar", action: { kind: "serve" } },
      { id: "worship-team", title: "Worship Team Application", subtitle: "Musicians and vocalists start here.", systemImage: "music.mic", action: { kind: "form", formId: "10188", url: form("10188") } },
    ],
  },
  {
    id: "care",
    title: "Care & Prayer",
    steps: [
      { id: "prayer", title: "Prayer Request", subtitle: "Our prayer team would love to pray with you.", systemImage: "hands.and.sparkles.fill", action: { kind: "form", formId: "10182", url: form("10182") } },
      { id: "divorcecare", title: "DivorceCare", subtitle: "Find help and healing.", systemImage: "bandage.fill", action: { kind: "signup", signupId: "2148535", url: signup("2148535") } },
      { id: "contact", title: "Contact Us", subtitle: "Questions? We're here to help.", systemImage: "bubble.left.and.bubble.right.fill", action: { kind: "form", formId: "10174", url: form("10174") } },
    ],
  },
];

export const LINKS = {
  give: cc("/giving"),
  checkIns: cc("/check-ins"),
  myProfile: cc("/me/profile-and-household"),
  myRegistrations: cc("/registrations/reservations"),
  groups: cc("/groups"),
  registrations: cc("/registrations"),
  sermons: SERMON_CHANNEL.churchCenterUrl,
} as const;

/** Website pages the app pulls as primary content. Paths are relative to WEBSITE_BASE_URL. */
export const WEBSITE_PAGES = [
  { slug: "about", title: "About", path: "/about" },
  { slug: "visit", title: "Plan Your Visit", path: "/plan-a-visit" },
  { slug: "kids", title: "Horizon Kids", path: "/kids" },
  { slug: "youth", title: "Youth", path: "/youth" },
  { slug: "beliefs", title: "What We Believe", path: "/beliefs" },
  { slug: "contact", title: "Contact", path: "/contact" },
];

// Planning Center–backed endpoints. Every PCO path used here is listed with its purpose in
// docs/PCO_INTEGRATION.md.

import { CHECK_IN_EVENT_IDS, ORG, PUBLIC_GROUP_TYPE_IDS } from "./config.ts";
import {
  asArray,
  type Document,
  type Member,
  PCOClient,
  PCOError,
  related,
  relatedMany,
  relId,
  type Resource,
} from "./pco.ts";

type Attrs = Record<string, any>;

export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

function pick<T extends Attrs>(input: Attrs, allowed: readonly string[]): Partial<T> {
  const out: Attrs = {};
  for (const k of allowed) if (k in input) out[k] = input[k];
  return out as Partial<T>;
}

// ===========================================================================
// Groups

export interface GroupSummary {
  id: string;
  name: string;
  groupTypeId: string | null;
  groupTypeName: string | null;
  summary: string;
  descriptionHtml: string;
  schedule: string | null;
  imageUrl: string | null;
  membersCount: number;
  meetsOnline: boolean;
  location: { name: string | null; address: string | null; latitude: number | null; longitude: number | null; approximate: boolean } | null;
  enrollment: { status: string; strategy: string } | null;
  churchCenterUrl: string;
  tags: string[];
}

function mapGroup(doc: Document, g: Resource): GroupSummary {
  const a = g.attributes as Attrs;
  const type = related(doc, g, "group_type");
  const loc = related(doc, g, "location");
  const enr = related(doc, g, "enrollment");
  const la = loc?.attributes as Attrs | undefined;
  const display: string = la?.display_preference ?? "hidden";
  return {
    id: g.id,
    name: a.name,
    groupTypeId: type?.id ?? relId(g, "group_type") ?? null,
    groupTypeName: (type?.attributes as Attrs | undefined)?.name ?? null,
    summary: (a.description_as_plain_text ?? "").slice(0, 240),
    descriptionHtml: a.description ?? "",
    schedule: a.schedule ?? null,
    imageUrl: a.header_image?.medium ?? a.header_image?.original ?? null,
    membersCount: a.memberships_count ?? 0,
    meetsOnline: a.location_type_preference === "virtual",
    location:
      la && display !== "hidden"
        ? {
            name: la.name ?? null,
            // Only reveal the street address when the group leader chose "exact".
            address: display === "exact" ? la.full_formatted_address ?? null : null,
            latitude: la.latitude != null ? Number(la.latitude) : null,
            longitude: la.longitude != null ? Number(la.longitude) : null,
            approximate: display !== "exact",
          }
        : null,
    enrollment: enr ? { status: (enr.attributes as Attrs).status, strategy: (enr.attributes as Attrs).strategy } : null,
    churchCenterUrl: a.church_center_web_url ?? `${ORG.churchCenter}/groups`,
    tags: relatedMany(doc, g, "tags").map((t) => (t.attributes as Attrs).name),
  };
}

export async function listGroupTypes(pco: PCOClient) {
  const doc = await pco.getAll("/groups/v2/group_types");
  return asArray(doc.data)
    .filter((t) => PUBLIC_GROUP_TYPE_IDS.includes(t.id))
    .map((t) => ({ id: t.id, name: (t.attributes as Attrs).name, description: (t.attributes as Attrs).description ?? "" }));
}

export async function listGroups(pco: PCOClient): Promise<GroupSummary[]> {
  const all: GroupSummary[] = [];
  for (const typeId of PUBLIC_GROUP_TYPE_IDS) {
    const doc = await pco.getAll(`/groups/v2/group_types/${typeId}/groups`, {
      include: "group_type,location,enrollment,tags",
      "where[archive_status]": "not_archived",
    });
    for (const g of asArray(doc.data)) {
      if ((g.attributes as Attrs).archived_at) continue;
      const mapped = mapGroup(doc, g);
      if (mapped.enrollment?.status === "private") continue;
      all.push(mapped);
    }
  }
  return all.sort((a, b) => a.name.localeCompare(b.name));
}

// ===========================================================================
// Events (Registrations signups + Calendar)

export interface EventSummary {
  id: string;
  source: "registrations" | "calendar";
  title: string;
  summary: string;
  descriptionHtml: string;
  imageUrl: string | null;
  startsAt: string | null;
  endsAt: string | null;
  allDay: boolean;
  location: string | null;
  registrationUrl: string | null;
  detailsUrl: string;
  registrationOpen: boolean;
  atCapacity: boolean;
}

export async function listEvents(pco: PCOClient): Promise<EventSummary[]> {
  const [signups, calendar] = await Promise.allSettled([listSignups(pco), listCalendar(pco)]);
  const events = [
    ...(signups.status === "fulfilled" ? signups.value : []),
    ...(calendar.status === "fulfilled" ? calendar.value : []),
  ];
  if (signups.status === "rejected" && calendar.status === "rejected") throw signups.reason;

  // A signup also appears on the calendar. Keep the signup (it has the registration link).
  const seen = new Set(events.filter((e) => e.source === "registrations").map((e) => e.title.trim().toLowerCase()));
  const deduped = events.filter((e) => e.source === "registrations" || !seen.has(e.title.trim().toLowerCase()));
  return deduped.sort((a, b) => (a.startsAt ?? "9999").localeCompare(b.startsAt ?? "9999"));
}

async function listSignups(pco: PCOClient): Promise<EventSummary[]> {
  const doc = await pco.getAll("/registrations/v2/signups", {
    filter: "unarchived",
    include: "next_signup_time,signup_location",
  });
  return asArray(doc.data)
    .filter((s) => !(s.attributes as Attrs).archived)
    .map((s) => {
      const a = s.attributes as Attrs;
      const time = related(doc, s, "next_signup_time")?.attributes as Attrs | undefined;
      const loc = related(doc, s, "signup_location")?.attributes as Attrs | undefined;
      return {
        id: `reg-${s.id}`,
        source: "registrations" as const,
        title: String(a.name ?? "").trim(),
        summary: String(a.description ?? "").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim().slice(0, 200),
        descriptionHtml: a.description ?? "",
        imageUrl: a.logo_url ?? null,
        startsAt: time?.starts_at ?? null,
        endsAt: time?.ends_at ?? null,
        allDay: time?.all_day ?? false,
        location: loc?.formatted_address ?? loc?.name ?? null,
        registrationUrl: a.new_registration_url ?? null,
        detailsUrl: `${ORG.churchCenter}/registrations/events/${s.id}`,
        registrationOpen: a.open ?? !a.closed,
        atCapacity: a.at_maximum_capacity ?? false,
      };
    });
}

async function listCalendar(pco: PCOClient): Promise<EventSummary[]> {
  const doc = await pco.getAll(
    "/calendar/v2/event_instances",
    { filter: "future", order: "starts_at", include: "event" },
    3,
  );
  const out: EventSummary[] = [];
  const seenEvents = new Set<string>();
  for (const inst of asArray(doc.data)) {
    const ev = related(doc, inst, "event");
    if (!ev) continue;
    const e = ev.attributes as Attrs;
    if (!e.visible_in_church_center || e.approval_status !== "A") continue;
    if (seenEvents.has(ev.id)) continue; // show the next occurrence only
    seenEvents.add(ev.id);
    const i = inst.attributes as Attrs;
    out.push({
      id: `cal-${inst.id}`,
      source: "calendar",
      title: e.name,
      summary: e.summary ?? "",
      descriptionHtml: e.description ?? "",
      imageUrl: e.image_url ?? null,
      startsAt: i.published_starts_at ?? i.starts_at ?? null,
      endsAt: i.published_ends_at ?? i.ends_at ?? null,
      allDay: i.all_day_event ?? false,
      location: i.location ?? null,
      registrationUrl: e.registration_url ?? null,
      detailsUrl: i.church_center_url ?? `${ORG.churchCenter}/calendar`,
      registrationOpen: !!e.registration_url,
      atCapacity: false,
    });
  }
  return out;
}

// ===========================================================================
// Profile (People)

const PERSON_FIELDS = ["first_name", "last_name", "nickname", "birthdate", "anniversary", "gender"] as const;
const EMAIL_FIELDS = ["address", "location", "primary"] as const;
const PHONE_FIELDS = ["number", "location", "primary"] as const;
const ADDRESS_FIELDS = ["street_line_1", "street_line_2", "city", "state", "zip", "location", "primary"] as const;

async function loadPerson(pco: PCOClient, personId: string) {
  return pco.get(`/people/v2/people/${personId}`, {
    include: "emails,phone_numbers,addresses,households,primary_campus",
  });
}

export async function getProfile(pco: PCOClient, member: Member) {
  const doc = await loadPerson(pco, member.personId);
  const p = asArray(doc.data)[0]!;
  const a = p.attributes as Attrs;
  const household = relatedMany(doc, p, "households")[0];
  let householdMembers: { id: string; name: string; child: boolean; avatarUrl: string | null }[] = [];
  if (household) {
    const hh = await pco.get(`/people/v2/households/${household.id}`, { include: "people" });
    householdMembers = (hh.included ?? [])
      .filter((r) => r.type === "Person")
      .map((r) => ({
        id: r.id,
        name: (r.attributes as Attrs).name,
        child: !!(r.attributes as Attrs).child,
        avatarUrl: (r.attributes as Attrs).avatar ?? null,
      }));
  }
  return {
    id: p.id,
    firstName: a.first_name,
    lastName: a.last_name,
    nickname: a.nickname ?? null,
    name: a.name,
    birthdate: a.birthdate ?? null,
    anniversary: a.anniversary ?? null,
    gender: a.gender ?? null,
    avatarUrl: a.avatar ?? null,
    membership: a.membership ?? null,
    campus: (related(doc, p, "primary_campus")?.attributes as Attrs | undefined)?.name ?? null,
    emails: relatedMany(doc, p, "emails").map((e) => ({ id: e.id, ...pick(e.attributes as Attrs, EMAIL_FIELDS) })),
    phoneNumbers: relatedMany(doc, p, "phone_numbers").map((e) => ({ id: e.id, ...pick(e.attributes as Attrs, PHONE_FIELDS) })),
    addresses: relatedMany(doc, p, "addresses").map((e) => ({ id: e.id, ...pick(e.attributes as Attrs, ADDRESS_FIELDS) })),
    household: household ? { id: household.id, name: (household.attributes as Attrs).name, members: householdMembers } : null,
  };
}

export interface ProfileUpdate {
  person?: Attrs;
  emails?: (Attrs & { id?: string; _delete?: boolean })[];
  phoneNumbers?: (Attrs & { id?: string; _delete?: boolean })[];
  addresses?: (Attrs & { id?: string; _delete?: boolean })[];
}

/** Applies an allow-listed profile update, only touching records owned by the member. */
export async function updateProfile(pco: PCOClient, member: Member, update: ProfileUpdate) {
  const pid = member.personId;
  const current = await loadPerson(pco, pid);
  const me = asArray(current.data)[0]!;
  const owned = (rel: string) => new Set(relatedMany(current, me, rel).map((r) => r.id));

  if (update.person) {
    const attributes = pick(update.person, PERSON_FIELDS);
    if (Object.keys(attributes).length) {
      await pco.request("PATCH", `/people/v2/people/${pid}`, { body: { data: { type: "Person", id: pid, attributes } } });
    }
  }

  const sync = async (
    items: (Attrs & { id?: string; _delete?: boolean })[] | undefined,
    rel: string,
    collection: string,
    type: string,
    fields: readonly string[],
  ) => {
    if (!items) return;
    const mine = owned(rel);
    for (const item of items) {
      const attributes = pick(item, fields);
      if (item.id) {
        if (!mine.has(item.id)) throw new HttpError(403, `That ${type.toLowerCase()} isn't on your profile.`);
        if (item._delete) await pco.request("DELETE", `/people/v2/${collection}/${item.id}`);
        else await pco.request("PATCH", `/people/v2/${collection}/${item.id}`, { body: { data: { type, id: item.id, attributes } } });
      } else if (!item._delete) {
        await pco.request("POST", `/people/v2/people/${pid}/${collection}`, { body: { data: { type, attributes } } });
      }
    }
  };

  await sync(update.emails, "emails", "emails", "Email", EMAIL_FIELDS);
  await sync(update.phoneNumbers, "phone_numbers", "phone_numbers", "PhoneNumber", PHONE_FIELDS);
  await sync(update.addresses, "addresses", "addresses", "Address", ADDRESS_FIELDS);
  return getProfile(pco, member);
}

/**
 * Avatar upload: send the image to Planning Center's upload service, then set the returned
 * file id as the person's `avatar` attribute.
 */
export async function updateAvatar(pco: PCOClient, env: { PCO_APP_ID: string; PCO_SECRET: string }, member: Member, image: Blob) {
  if (image.size > 5 * 1024 * 1024) throw new HttpError(413, "Photo must be under 5 MB.");
  const form = new FormData();
  form.append("file", image, "avatar.jpg");
  const res = await fetch("https://upload.planningcenteronline.com/v2/files", {
    method: "POST",
    headers: { Authorization: "Basic " + btoa(`${env.PCO_APP_ID}:${env.PCO_SECRET}`) },
    body: form,
  });
  if (!res.ok) throw new PCOError(res.status, await res.text());
  const uploaded = (await res.json()) as Document;
  const fileId = asArray(uploaded.data)[0]?.id;
  if (!fileId) throw new HttpError(502, "Upload failed.");
  await pco.request("PATCH", `/people/v2/people/${member.personId}`, {
    body: { data: { type: "Person", id: member.personId, attributes: { avatar: fileId } } },
  });
  return getProfile(pco, member);
}

// ===========================================================================
// Serving (Services)

export async function getServing(pco: PCOClient, member: Member) {
  const pid = member.personId;
  let schedulesDoc: Document;
  try {
    schedulesDoc = await pco.get(`/services/v2/people/${pid}/schedules`, { filter: "future", per_page: 50 });
  } catch (e) {
    if (!(e instanceof PCOError) || e.status >= 500) throw e;
    schedulesDoc = await pco.get(`/services/v2/people/${pid}/schedules`, { per_page: 100, order: "-sort_date" });
  }
  const now = Date.now() - 24 * 3600_000;
  const schedules = asArray(schedulesDoc.data)
    .map((s) => {
      const a = s.attributes as Attrs;
      return {
        id: s.id,
        serviceTypeName: a.service_type_name,
        teamName: a.team_name,
        positionName: a.team_position_name,
        dates: a.dates,
        shortDates: a.short_dates,
        sortDate: a.sort_date,
        timesDescription: a.position_display_times ?? null,
        status: a.status, // "U" unconfirmed, "C" confirmed, "D" declined
        declineReason: a.decline_reason ?? null,
        canAcceptPartial: !!a.can_accept_partial,
        planVisible: !!(a.plan_visible_to_me ?? a.plan_visible),
        respondsTo: a.responds_to_name ?? null,
        planId: relId(s, "plan"),
        serviceTypeId: relId(s, "service_type"),
        planPersonId: relId(s, "plan_person"),
      };
    })
    .filter((s) => !s.sortDate || Date.parse(s.sortDate) >= now)
    .sort((a, b) => String(a.sortDate).localeCompare(String(b.sortDate)));

  const [blockoutsDoc, assignmentsDoc, servicesPerson] = await Promise.all([
    pco.get(`/services/v2/people/${pid}/blockouts`, { filter: "future", per_page: 50 }).catch(() => ({ data: [] }) as Document),
    pco.get(`/services/v2/people/${pid}/person_team_position_assignments`, { include: "team_position", per_page: 100 }).catch(() => ({ data: [] }) as Document),
    pco.get(`/services/v2/people/${pid}`).catch(() => null),
  ]);

  const sp = servicesPerson ? (asArray(servicesPerson.data)[0]?.attributes as Attrs | undefined) : undefined;
  return {
    schedules,
    blockouts: asArray(blockoutsDoc.data).map((b) => {
      const a = b.attributes as Attrs;
      return { id: b.id, reason: a.reason ?? "", startsAt: a.starts_at, endsAt: a.ends_at, repeatFrequency: a.repeat_frequency ?? "no_repeat" };
    }),
    positions: asArray(assignmentsDoc.data).map((p) => {
      const a = p.attributes as Attrs;
      const pos = related(assignmentsDoc, p, "team_position");
      return {
        id: p.id,
        positionName: (pos?.attributes as Attrs | undefined)?.name ?? "Team position",
        schedulePreference: a.schedule_preference ?? "Every week",
        preferredWeeks: (a.preferred_weeks ?? []) as string[],
      };
    }),
    preferences: {
      maxPlansPerMonth: sp?.preferred_max_plans_per_month ?? null,
      maxPlansPerDay: sp?.preferred_max_plans_per_day ?? null,
    },
  };
}

async function ownSchedule(pco: PCOClient, member: Member, scheduleId: string) {
  const doc = await pco.get(`/services/v2/people/${member.personId}/schedules/${scheduleId}`).catch(() => null);
  if (!doc) throw new HttpError(404, "That serving request wasn't found on your schedule.");
  return asArray(doc.data)[0]!;
}

/** Accepts or declines a serving request. */
export async function respondToSchedule(
  pco: PCOClient,
  member: Member,
  scheduleId: string,
  response: "accept" | "decline",
  reason?: string,
) {
  const schedule = await ownSchedule(pco, member, scheduleId);
  const base = `/services/v2/people/${member.personId}/schedules/${scheduleId}`;
  try {
    // Preferred: the Schedule resource's accept/decline actions.
    await pco.request("POST", `${base}/${response}`, {
      body: response === "decline" ? { data: { attributes: { reason: reason ?? "" } } } : { data: { attributes: {} } },
    });
  } catch (e) {
    if (!(e instanceof PCOError) || ![404, 405, 422].includes(e.status)) throw e;
    // Fallback: set the PlanPerson status directly.
    const st = relId(schedule, "service_type");
    const plan = relId(schedule, "plan");
    const pp = relId(schedule, "plan_person");
    if (!st || !plan || !pp) throw e;
    await pco.request("PATCH", `/services/v2/service_types/${st}/plans/${plan}/team_members/${pp}`, {
      body: {
        data: {
          type: "PlanPerson",
          id: pp,
          attributes: response === "accept" ? { status: "C" } : { status: "D", decline_reason: reason ?? "" },
        },
      },
    });
  }
  return getServing(pco, member);
}

export async function createBlockout(pco: PCOClient, member: Member, input: Attrs) {
  const startsAt = String(input.startsAt ?? "");
  const endsAt = String(input.endsAt ?? "");
  if (!Date.parse(startsAt) || !Date.parse(endsAt) || Date.parse(endsAt) < Date.parse(startsAt)) {
    throw new HttpError(400, "Choose a valid start and end date.");
  }
  await pco.request("POST", `/services/v2/people/${member.personId}/blockouts`, {
    body: {
      data: {
        type: "Blockout",
        attributes: {
          reason: String(input.reason ?? "").slice(0, 255),
          starts_at: startsAt,
          ends_at: endsAt,
          repeat_frequency: "no_repeat",
        },
      },
    },
  });
  return getServing(pco, member);
}

export async function deleteBlockout(pco: PCOClient, member: Member, blockoutId: string) {
  // Scoped to the member's own person path, so another person's blockout can't be deleted.
  await pco.request("DELETE", `/services/v2/people/${member.personId}/blockouts/${blockoutId}`);
  return getServing(pco, member);
}

export const SCHEDULE_PREFERENCES = [
  "Every week",
  "Every other week (A)",
  "Every other week (B)",
  "Every 3rd week",
  "Every 4th week",
  "Every 5th week",
  "Every 6th week",
  "Once a month",
  "Twice a month",
  "Three times a month",
  "Choose weeks",
] as const;

export async function updateServingPreferences(pco: PCOClient, member: Member, input: Attrs) {
  const pid = member.personId;
  for (const pos of (input.positions ?? []) as Attrs[]) {
    if (!SCHEDULE_PREFERENCES.includes(pos.schedulePreference)) throw new HttpError(400, "Unknown schedule preference.");
    const attributes: Attrs = { schedule_preference: pos.schedulePreference };
    if (pos.schedulePreference === "Choose weeks") {
      attributes.preferred_weeks = ((pos.preferredWeeks ?? []) as string[]).filter((w) => ["1", "2", "3", "4", "5"].includes(w));
    }
    await pco.request("PATCH", `/services/v2/people/${pid}/person_team_position_assignments/${pos.id}`, {
      body: { data: { type: "PersonTeamPositionAssignment", id: String(pos.id), attributes } },
    });
  }
  if (input.preferences) {
    const attributes: Attrs = {};
    if ("maxPlansPerMonth" in input.preferences) attributes.preferred_max_plans_per_month = input.preferences.maxPlansPerMonth;
    if ("maxPlansPerDay" in input.preferences) attributes.preferred_max_plans_per_day = input.preferences.maxPlansPerDay;
    if (Object.keys(attributes).length) {
      await pco.request("PATCH", `/services/v2/people/${pid}`, { body: { data: { type: "Person", id: pid, attributes } } });
    }
  }
  return getServing(pco, member);
}

// ===========================================================================
// My groups + leader tools (Groups)

export async function getMyGroups(pco: PCOClient, member: Member) {
  const doc = await pco.getAll(`/groups/v2/people/${member.personId}/memberships`, { include: "group" });
  const memberships = asArray(doc.data);
  return Promise.all(
    memberships.map(async (m) => {
      const g = related(doc, m, "group");
      const ga = (g?.attributes ?? {}) as Attrs;
      const groupId = g?.id ?? relId(m, "group")!;
      const events = await pco
        .get(`/groups/v2/groups/${groupId}/events`, { filter: "upcoming", order: "starts_at", per_page: 5 })
        .catch(() => ({ data: [] }) as Document);
      return {
        membershipId: m.id,
        role: (m.attributes as Attrs).role as "member" | "leader",
        group: {
          id: groupId,
          name: ga.name ?? "Group",
          schedule: ga.schedule ?? null,
          imageUrl: ga.header_image?.medium ?? null,
          churchCenterUrl: ga.church_center_web_url ?? `${ORG.churchCenter}/groups`,
          membersCount: ga.memberships_count ?? 0,
        },
        upcomingEvents: asArray(events.data).map((e) => mapGroupEvent(e, ga.church_center_web_url)),
      };
    }),
  );
}

function mapGroupEvent(e: Resource, groupUrl?: string) {
  const a = e.attributes as Attrs;
  return {
    id: e.id,
    name: a.name,
    startsAt: a.starts_at,
    endsAt: a.ends_at,
    canceled: !!a.canceled,
    location: a.location_type_preference === "virtual" ? a.virtual_location_url ?? "Online" : null,
    // Church Center's event page, where leaders take attendance.
    churchCenterUrl: a.church_center_web_url ?? (groupUrl ? `${groupUrl}/events/${e.id}` : `${ORG.churchCenter}/groups`),
  };
}

async function requireLeader(pco: PCOClient, member: Member, groupId: string) {
  const doc = await pco.getAll(`/groups/v2/people/${member.personId}/memberships`);
  const isLeader = asArray(doc.data).some(
    (m) => relId(m, "group") === groupId && (m.attributes as Attrs).role === "leader",
  );
  if (!isLeader) throw new HttpError(403, "Only group leaders can see this.");
}

/** Leader view: roster and recent attendance for one group. */
export async function getLeaderGroup(pco: PCOClient, member: Member, groupId: string) {
  await requireLeader(pco, member, groupId);
  const [groupDoc, rosterDoc, pastDoc, upcomingDoc] = await Promise.all([
    pco.get(`/groups/v2/groups/${groupId}`),
    pco.getAll(`/groups/v2/groups/${groupId}/memberships`, { include: "person" }),
    pco.get(`/groups/v2/groups/${groupId}/events`, { filter: "past", order: "-starts_at", per_page: 6 }),
    pco.get(`/groups/v2/groups/${groupId}/events`, { filter: "upcoming", order: "starts_at", per_page: 3 }),
  ]);
  const groupUrl = (asArray(groupDoc.data)[0]?.attributes as Attrs | undefined)?.church_center_web_url;

  const roster = asArray(rosterDoc.data).map((m) => {
    const p = related(rosterDoc, m, "person");
    const pa = (p?.attributes ?? {}) as Attrs;
    return {
      personId: p?.id ?? relId(m, "person"),
      name: [pa.first_name, pa.last_name].filter(Boolean).join(" ") || "Member",
      avatarUrl: pa.avatar_url ?? null,
      role: (m.attributes as Attrs).role,
      joinedAt: (m.attributes as Attrs).joined_at ?? null,
    };
  });

  const recent = await Promise.all(
    asArray(pastDoc.data).map(async (e) => {
      const att = await pco.getAll(`/groups/v2/events/${e.id}/attendances`).catch(() => ({ data: [] }) as Document);
      const rows = asArray(att.data);
      return {
        event: mapGroupEvent(e, groupUrl),
        attendedCount: rows.filter((r) => (r.attributes as Attrs).attended).length,
        recorded: rows.length > 0,
        attendance: rows.map((r) => ({ personId: relId(r, "person"), attended: !!(r.attributes as Attrs).attended })),
      };
    }),
  );

  return {
    roster,
    upcomingEvents: asArray(upcomingDoc.data).map((e) => mapGroupEvent(e, groupUrl)),
    recentEvents: recent,
  };
}

// ===========================================================================
// Giving

let fundCache: { at: number; names: Map<string, string> } | null = null;

async function fundNames(pco: PCOClient) {
  if (fundCache && Date.now() - fundCache.at < 3600_000) return fundCache.names;
  const doc = await pco.getAll("/giving/v2/funds");
  const names = new Map(asArray(doc.data).map((f) => [f.id, (f.attributes as Attrs).name as string]));
  fundCache = { at: Date.now(), names };
  return names;
}

export async function getGiving(pco: PCOClient, member: Member) {
  const pid = member.personId;
  const year = new Date().getUTCFullYear();
  const [donations, recurring, funds] = await Promise.all([
    pco.get(`/giving/v2/people/${pid}/donations`, { include: "designations", order: "-received_at", per_page: 50 }),
    pco.get(`/giving/v2/people/${pid}/recurring_donations`, { include: "designations" }).catch(() => ({ data: [] }) as Document),
    fundNames(pco).catch(() => new Map<string, string>()),
  ]);
  const gifts = asArray(donations.data).map((d) => {
    const a = d.attributes as Attrs;
    return {
      id: d.id,
      amountCents: a.amount_cents,
      currency: a.amount_currency ?? "USD",
      receivedAt: a.received_at,
      method: a.payment_brand ? `${a.payment_brand} •••• ${a.payment_last4 ?? ""}`.trim() : a.payment_method ?? "",
      refunded: !!a.refunded,
      funds: relatedMany(donations, d, "designations").map((des) => funds.get(relId(des, "fund") ?? "") ?? "General"),
    };
  });
  const ytd = gifts
    .filter((g) => !g.refunded && g.receivedAt && new Date(g.receivedAt).getUTCFullYear() === year)
    .reduce((s, g) => s + (g.amountCents ?? 0), 0);
  return {
    yearToDateCents: ytd,
    year,
    gifts,
    recurring: asArray(recurring.data).map((r) => {
      const a = r.attributes as Attrs;
      return {
        id: r.id,
        amountCents: a.amount_cents,
        schedule: a.schedule ?? a.frequency ?? null,
        nextOccurrence: a.next_occurrence ?? null,
        status: a.status ?? "active",
      };
    }),
  };
}

// ===========================================================================
// Check-Ins

/** Whether any phone-check-in event is open right now (between shows_at and hides_at). */
export async function getCheckInStatus(pco: PCOClient) {
  const now = Date.now();
  const open: { eventId: string; eventName: string; startsAt: string }[] = [];
  const events = await pco.get("/check-ins/v2/events", { "where[id]": CHECK_IN_EVENT_IDS.join(",") }).catch(() => null);
  const names = new Map(events ? asArray(events.data).map((e) => [e.id, (e.attributes as Attrs).name as string]) : []);
  await Promise.all(
    CHECK_IN_EVENT_IDS.map(async (id) => {
      const doc = await pco.get(`/check-ins/v2/events/${id}/event_times`, { order: "-starts_at", per_page: 5 }).catch(() => null);
      for (const t of doc ? asArray(doc.data) : []) {
        const a = t.attributes as Attrs;
        const shows = Date.parse(a.shows_at ?? a.starts_at);
        const hides = Date.parse(a.hides_at ?? a.ends_at ?? a.starts_at) || shows + 3 * 3600_000;
        if (shows <= now && now <= hides) open.push({ eventId: id, eventName: names.get(id) ?? "Check-in", startsAt: a.starts_at });
      }
    }),
  );
  return { open: open.length > 0, events: open };
}

/** Recent check-ins for the member's household (shows security codes to parents). */
export async function getMyCheckIns(pco: PCOClient, member: Member, householdPersonIds: string[]) {
  const ids = [member.personId, ...householdPersonIds.filter((id) => id !== member.personId)].slice(0, 8);
  const since = Date.now() - 12 * 3600_000;
  const rows = await Promise.all(
    ids.map(async (id) => {
      const doc = await pco.get(`/check-ins/v2/people/${id}/check_ins`, { include: "event", order: "-created_at", per_page: 3 }).catch(() => null);
      return doc
        ? asArray(doc.data).map((c) => {
            const a = c.attributes as Attrs;
            return {
              id: c.id,
              personId: id,
              name: [a.first_name, a.last_name].filter(Boolean).join(" "),
              eventName: (related(doc, c, "event")?.attributes as Attrs | undefined)?.name ?? "Check-in",
              securityCode: a.security_code ?? null,
              checkedInAt: a.created_at,
              checkedOutAt: a.checked_out_at ?? null,
            };
          })
        : [];
    }),
  );
  return rows.flat().filter((r) => Date.parse(r.checkedInAt) >= since);
}

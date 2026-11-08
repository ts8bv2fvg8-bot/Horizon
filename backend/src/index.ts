// Horizon app API: a thin backend-for-frontend between the iOS app, Planning Center and the
// church website. It runs on Cloudflare Workers but has no Workers-only dependencies apart
// from the optional KV cache.

import { CAMPUSES, LINKS, NEXT_STEPS, ORG, SERMON_CHANNEL } from "./config.ts";
import { detectPlatform, fetchHome, fetchPage, parseRss } from "./content.ts";
import {
  createBlockout,
  deleteBlockout,
  getCheckInStatus,
  getGiving,
  getLeaderGroup,
  getMyCheckIns,
  getMyGroups,
  getProfile,
  getServing,
  HttpError,
  listEvents,
  listGroups,
  listGroupTypes,
  respondToSchedule,
  SCHEDULE_PREFERENCES,
  updateAvatar,
  updateProfile,
  updateServingPreferences,
} from "./handlers.ts";
import { type Env, type Member, PCOClient, PCOError, verifyMember } from "./pco.ts";

const json = (body: unknown, status = 200, maxAge = 0) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": maxAge ? `public, max-age=${maxAge}` : "private, no-store",
    },
  });

/** Caches public responses in KV (if bound) and in the Workers cache. */
async function cached<T>(env: Env, key: string, ttlSeconds: number, load: () => Promise<T>): Promise<T> {
  if (env.CACHE) {
    const hit = await env.CACHE.get(key, "json");
    if (hit) return hit as T;
  }
  const value = await load();
  if (env.CACHE) await env.CACHE.put(key, JSON.stringify(value), { expirationTtl: Math.max(60, ttlSeconds) });
  return value;
}

async function requireMember(req: Request): Promise<Member> {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!token) throw new HttpError(401, "Sign in with Planning Center to continue.");
  try {
    return await verifyMember(token, ORG.pcoOrganizationId);
  } catch (e) {
    if (e instanceof PCOError) throw new HttpError(e.status === 401 ? 401 : 403, e.status === 401 ? "Your session expired. Please sign in again." : e.message);
    throw e;
  }
}

type Handler = (ctx: { req: Request; env: Env; pco: PCOClient; params: string[]; url: URL }) => Promise<Response>;

const routes: [method: string, pattern: RegExp, handler: Handler][] = [
  // ---- Public ------------------------------------------------------------
  ["GET", /^\/v1\/config$/, async () =>
    json({ organization: ORG, campuses: CAMPUSES, links: LINKS, nextSteps: NEXT_STEPS, sermonChannel: SERMON_CHANNEL, schedulePreferences: SCHEDULE_PREFERENCES }, 200, 300)],

  ["GET", /^\/v1\/content\/home$/, async ({ env }) => {
    const data = await cached(env, "content:home", 900, async () => {
      const platform = await cached(env, "content:platform", 86400, () => detectPlatform(env.WEBSITE_BASE_URL));
      return fetchHome(env.WEBSITE_BASE_URL, platform);
    });
    return json(data, 200, 300);
  }],

  ["GET", /^\/v1\/content\/pages\/([a-z0-9-]+)$/, async ({ env, params }) => {
    const slug = params[0]!;
    const data = await cached(env, `content:page:${slug}`, 3600, async () => {
      const platform = await cached(env, "content:platform", 86400, () => detectPlatform(env.WEBSITE_BASE_URL));
      return fetchPage(env.WEBSITE_BASE_URL, slug, platform);
    });
    return data ? json(data, 200, 600) : json({ error: "Page not found" }, 404);
  }],

  ["GET", /^\/v1\/sermons$/, async ({ env }) => {
    const data = await cached(env, "sermons", 900, async () => {
      const res = await fetch(SERMON_CHANNEL.podcastFeedUrl);
      if (!res.ok) throw new HttpError(502, "Couldn't load messages.");
      return parseRss(await res.text());
    });
    return json(data, 200, 300);
  }],

  ["GET", /^\/v1\/group-types$/, async ({ env, pco }) => json(await cached(env, "group-types", 3600, () => listGroupTypes(pco)), 200, 600)],
  ["GET", /^\/v1\/groups$/, async ({ env, pco }) => json(await cached(env, "groups", 900, () => listGroups(pco)), 200, 300)],
  ["GET", /^\/v1\/events$/, async ({ env, pco }) => json(await cached(env, "events", 600, () => listEvents(pco)), 200, 300)],
  ["GET", /^\/v1\/check-ins\/status$/, async ({ env, pco }) => json(await cached(env, "checkin-status", 60, () => getCheckInStatus(pco)), 200, 60)],

  // ---- Signed-in member --------------------------------------------------
  ["GET", /^\/v1\/me$/, async ({ req, pco }) => json(await getProfile(pco, await requireMember(req)))],
  ["PATCH", /^\/v1\/me$/, async ({ req, pco }) => json(await updateProfile(pco, await requireMember(req), await req.json()))],
  ["PUT", /^\/v1\/me\/avatar$/, async ({ req, env, pco }) => json(await updateAvatar(pco, env, await requireMember(req), await req.blob()))],

  ["GET", /^\/v1\/me\/serving$/, async ({ req, pco }) => json(await getServing(pco, await requireMember(req)))],
  ["POST", /^\/v1\/me\/serving\/schedules\/(\d+)\/(accept|decline)$/, async ({ req, pco, params }) => {
    const body = (await req.json().catch(() => ({}))) as { reason?: string };
    return json(await respondToSchedule(pco, await requireMember(req), params[0]!, params[1] as "accept" | "decline", body.reason));
  }],
  ["POST", /^\/v1\/me\/serving\/blockouts$/, async ({ req, pco }) => json(await createBlockout(pco, await requireMember(req), await req.json()))],
  ["DELETE", /^\/v1\/me\/serving\/blockouts\/(\d+)$/, async ({ req, pco, params }) => json(await deleteBlockout(pco, await requireMember(req), params[0]!))],
  ["PATCH", /^\/v1\/me\/serving\/preferences$/, async ({ req, pco }) => json(await updateServingPreferences(pco, await requireMember(req), await req.json()))],

  ["GET", /^\/v1\/me\/groups$/, async ({ req, pco }) => json(await getMyGroups(pco, await requireMember(req)))],
  ["GET", /^\/v1\/me\/groups\/(\d+)\/leader$/, async ({ req, pco, params }) => json(await getLeaderGroup(pco, await requireMember(req), params[0]!))],

  ["GET", /^\/v1\/me\/giving$/, async ({ req, pco }) => json(await getGiving(pco, await requireMember(req)))],

  ["GET", /^\/v1\/me\/check-ins$/, async ({ req, pco }) => {
    const member = await requireMember(req);
    const profile = await getProfile(pco, member);
    return json(await getMyCheckIns(pco, member, profile.household?.members.map((m) => m.id) ?? []));
  }],
];

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);
    const pco = new PCOClient(env);
    for (const [method, pattern, handler] of routes) {
      if (req.method !== method) continue;
      const m = url.pathname.match(pattern);
      if (!m) continue;
      try {
        return await handler({ req, env, pco, params: m.slice(1), url });
      } catch (e) {
        if (e instanceof HttpError) return json({ error: e.message }, e.status);
        if (e instanceof PCOError) {
          console.error(e.message);
          return json({ error: "Planning Center couldn't complete that request." }, e.status === 404 ? 404 : 502);
        }
        console.error(e);
        return json({ error: "Something went wrong." }, 500);
      }
    }
    return json({ error: "Not found" }, 404);
  },
};

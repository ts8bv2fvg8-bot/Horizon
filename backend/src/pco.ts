// Minimal Planning Center JSON:API client.
//
// Two kinds of credentials:
//  * The org credential (Personal Access Token from an admin account, HTTP Basic). Used for
//    public data (groups, signups, calendar) and for actions taken on behalf of a member
//    whose identity has already been verified.
//  * The member's own OAuth access token. Used only to identify who is calling
//    (GET /people/v2/me). Members often have no admin permissions in People, Groups or
//    Giving, so we never depend on their token having those rights.

export const PCO_API = "https://api.planningcenteronline.com";

export interface Env {
  PCO_APP_ID: string;
  PCO_SECRET: string;
  WEBSITE_BASE_URL: string;
  CHURCH_CENTER_BASE_URL: string;
  CACHE?: KVNamespace;
}

export interface Resource<A = Record<string, unknown>> {
  type: string;
  id: string;
  attributes: A;
  relationships?: Record<string, { data: { type: string; id: string } | { type: string; id: string }[] | null }>;
  links?: Record<string, string | null>;
}

export interface Document<A = Record<string, unknown>> {
  data: Resource<A> | Resource<A>[];
  included?: Resource[];
  meta?: { total_count?: number; count?: number; next?: { offset: number } };
  links?: { next?: string };
}

export class PCOError extends Error {
  constructor(public status: number, public body: string) {
    super(`Planning Center responded ${status}: ${body.slice(0, 300)}`);
  }
}

type Query = Record<string, string | number | undefined>;

function buildUrl(path: string, query?: Query): string {
  const url = new URL(path.startsWith("http") ? path : `${PCO_API}${path}`);
  for (const [k, v] of Object.entries(query ?? {})) {
    if (v !== undefined) url.searchParams.set(k, String(v));
  }
  return url.toString();
}

export class PCOClient {
  private auth: string;

  constructor(env: Pick<Env, "PCO_APP_ID" | "PCO_SECRET">) {
    this.auth = "Basic " + btoa(`${env.PCO_APP_ID}:${env.PCO_SECRET}`);
  }

  async request<A = Record<string, unknown>>(
    method: string,
    path: string,
    opts: { query?: Query; body?: unknown } = {},
  ): Promise<Document<A>> {
    const url = buildUrl(path, opts.query);
    for (let attempt = 0; attempt < 3; attempt++) {
      const res = await fetch(url, {
        method,
        headers: {
          Authorization: this.auth,
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
      });
      // PCO rate limit: 100 requests / 20 seconds per user. Honor Retry-After.
      if (res.status === 429) {
        const wait = Number(res.headers.get("Retry-After") ?? "2");
        await new Promise((r) => setTimeout(r, Math.min(wait, 10) * 1000));
        continue;
      }
      if (res.status === 204) return { data: [] };
      const text = await res.text();
      if (!res.ok) throw new PCOError(res.status, text);
      return text ? (JSON.parse(text) as Document<A>) : { data: [] };
    }
    throw new PCOError(429, "Rate limited by Planning Center");
  }

  get<A = Record<string, unknown>>(path: string, query?: Query) {
    return this.request<A>("GET", path, { query });
  }

  /** Follows `links.next` up to `maxPages` and merges data + included. */
  async getAll<A = Record<string, unknown>>(path: string, query?: Query, maxPages = 10): Promise<Document<A>> {
    let doc = await this.get<A>(path, { per_page: 100, ...query });
    const data = asArray(doc.data);
    const included = [...(doc.included ?? [])];
    let pages = 1;
    while (doc.links?.next && pages < maxPages) {
      doc = await this.get<A>(doc.links.next);
      data.push(...asArray(doc.data));
      included.push(...(doc.included ?? []));
      pages++;
    }
    return { data, included, meta: { total_count: data.length } };
  }
}

export function asArray<T>(v: T | T[]): T[] {
  return Array.isArray(v) ? v : [v];
}

/** Looks up an `included` resource referenced by a relationship. */
export function related(doc: Document, res: Resource, name: string): Resource | undefined {
  const rel = res.relationships?.[name]?.data;
  if (!rel || Array.isArray(rel)) return undefined;
  return doc.included?.find((i) => i.type === rel.type && i.id === rel.id);
}

export function relatedMany(doc: Document, res: Resource, name: string): Resource[] {
  const rel = res.relationships?.[name]?.data;
  if (!rel) return [];
  const refs = Array.isArray(rel) ? rel : [rel];
  return refs
    .map((r) => doc.included?.find((i) => i.type === r.type && i.id === r.id))
    .filter((r): r is Resource => !!r);
}

export function relId(res: Resource, name: string): string | undefined {
  const rel = res.relationships?.[name]?.data;
  return rel && !Array.isArray(rel) ? rel.id : undefined;
}

// ---------------------------------------------------------------------------
// Member identity

export interface Member {
  personId: string;
  name: string;
  organizationId: string;
}

const identityCache = new Map<string, { member: Member; expires: number }>();

/**
 * Verifies a member's OAuth access token by calling GET /people/v2/me with it.
 * Any signed-in Planning Center person can read their own /me record, regardless of
 * admin permissions. Cached in memory for 5 minutes per token.
 */
export async function verifyMember(accessToken: string, expectedOrgId: string): Promise<Member> {
  const cached = identityCache.get(accessToken);
  if (cached && cached.expires > Date.now()) return cached.member;

  const res = await fetch(`${PCO_API}/people/v2/me?include=organization`, {
    headers: { Authorization: `Bearer ${accessToken}`, Accept: "application/json" },
  });
  if (!res.ok) throw new PCOError(res.status === 401 ? 401 : 403, await res.text());
  const doc = (await res.json()) as Document<{ name: string }>;
  const me = asArray(doc.data)[0]!;
  const orgId = doc.included?.find((i) => i.type === "Organization")?.id ?? relId(me, "organization");
  if (orgId && orgId !== expectedOrgId) {
    throw new PCOError(403, "This Planning Center account belongs to a different organization.");
  }
  const member = { personId: me.id, name: me.attributes.name, organizationId: orgId ?? expectedOrgId };
  identityCache.set(accessToken, { member, expires: Date.now() + 5 * 60_000 });
  return member;
}

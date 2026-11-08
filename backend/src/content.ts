// Pulls primary content from www.horizoncommunity.church and normalizes it for the app.
//
// The website's platform is detected at runtime so the app keeps working if the site moves
// between WordPress, Squarespace or something else:
//   1. WordPress REST API   (/wp-json/wp/v2/...)
//   2. Squarespace JSON     (?format=json)
//   3. Plain HTML           (Open Graph tags + the <main>/<article> body)

import { WEBSITE_PAGES } from "./config.ts";

export interface WebPage {
  slug: string;
  title: string;
  summary: string;
  imageUrl: string | null;
  html: string;
  url: string;
  updatedAt: string | null;
}

export interface Announcement {
  id: string;
  title: string;
  summary: string;
  imageUrl: string | null;
  url: string;
  publishedAt: string | null;
}

export interface HomeContent {
  hero: { title: string; subtitle: string; imageUrl: string | null; url: string };
  announcements: Announcement[];
  pages: { slug: string; title: string }[];
  source: Platform;
}

type Platform = "wordpress" | "squarespace" | "html";

const UA = { "User-Agent": "HorizonChurchApp/1.0 (+https://www.horizoncommunity.church)" };

export async function detectPlatform(base: string): Promise<Platform> {
  try {
    const wp = await fetch(`${base}/wp-json/`, { headers: UA });
    if (wp.ok && (wp.headers.get("content-type") ?? "").includes("json")) return "wordpress";
  } catch { /* fall through */ }
  try {
    const sq = await fetch(`${base}/?format=json`, { headers: UA });
    if (sq.ok && (sq.headers.get("content-type") ?? "").includes("json")) return "squarespace";
  } catch { /* fall through */ }
  return "html";
}

// ---------------------------------------------------------------------------
// HTML helpers (Workers have no DOMParser, so keep this deliberately small)

export function decodeEntities(s: string): string {
  return s
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, '"')
    .replace(/&#039;|&apos;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&rsquo;|&lsquo;/g, "'")
    .replace(/&rdquo;|&ldquo;/g, '"')
    .replace(/&ndash;/g, "–")
    .replace(/&mdash;/g, "—")
    .replace(/&hellip;/g, "…");
}

export function stripTags(html: string): string {
  return decodeEntities(html.replace(/<(script|style)[\s\S]*?<\/\1>/gi, "").replace(/<[^>]+>/g, " "))
    .replace(/\s+/g, " ")
    .trim();
}

export function meta(html: string, property: string): string | null {
  const re = new RegExp(
    `<meta[^>]+(?:property|name)=["']${property}["'][^>]*content=["']([^"']*)["']|<meta[^>]+content=["']([^"']*)["'][^>]*(?:property|name)=["']${property}["']`,
    "i",
  );
  const m = html.match(re);
  return m ? decodeEntities(m[1] ?? m[2] ?? "") : null;
}

/** Removes scripts, styles, nav, header, footer, forms and inline event handlers. */
export function sanitizeHtml(html: string): string {
  return html
    .replace(/<(script|style|noscript|iframe|nav|header|footer|form)[\s\S]*?<\/\1>/gi, "")
    .replace(/\son\w+=("[^"]*"|'[^']*')/gi, "")
    .replace(/<!--[\s\S]*?-->/g, "")
    .trim();
}

export function mainBody(html: string): string {
  const pick =
    html.match(/<main[\s\S]*?>([\s\S]*?)<\/main>/i)?.[1] ??
    html.match(/<article[\s\S]*?>([\s\S]*?)<\/article>/i)?.[1] ??
    html.match(/<body[\s\S]*?>([\s\S]*?)<\/body>/i)?.[1] ??
    html;
  return sanitizeHtml(pick);
}

function absolutize(html: string, base: string): string {
  return html.replace(/(src|href)=["'](\/[^"']*)["']/gi, (_, attr, path) => `${attr}="${base}${path}"`);
}

// ---------------------------------------------------------------------------
// Pages

export async function fetchPage(base: string, slug: string, platform: Platform): Promise<WebPage | null> {
  const def = WEBSITE_PAGES.find((p) => p.slug === slug) ?? { slug, title: slug, path: `/${slug}` };
  const url = `${base}${def.path}`;

  if (platform === "wordpress") {
    const res = await fetch(`${base}/wp-json/wp/v2/pages?slug=${encodeURIComponent(def.path.replace(/^\/|\/$/g, ""))}&_embed=1`, { headers: UA });
    if (res.ok) {
      const items = (await res.json()) as WPItem[];
      const p = items[0];
      if (p) {
        return {
          slug,
          title: stripTags(p.title.rendered),
          summary: stripTags(p.excerpt?.rendered ?? "").slice(0, 280),
          imageUrl: p._embedded?.["wp:featuredmedia"]?.[0]?.source_url ?? null,
          html: absolutize(sanitizeHtml(p.content.rendered), base),
          url: p.link,
          updatedAt: p.modified_gmt ? `${p.modified_gmt}Z` : null,
        };
      }
    }
  }

  if (platform === "squarespace") {
    const res = await fetch(`${url}?format=json`, { headers: UA });
    if (res.ok) {
      const j = (await res.json()) as { collection?: { title?: string; description?: string }; mainContent?: string; website?: { logoImageUrl?: string } };
      if (j.mainContent) {
        return {
          slug,
          title: j.collection?.title ?? def.title,
          summary: stripTags(j.collection?.description ?? "").slice(0, 280),
          imageUrl: null,
          html: absolutize(sanitizeHtml(j.mainContent), base),
          url,
          updatedAt: null,
        };
      }
    }
  }

  const res = await fetch(url, { headers: UA });
  if (!res.ok) return null;
  const html = await res.text();
  return {
    slug,
    title: meta(html, "og:title") ?? def.title,
    summary: meta(html, "og:description") ?? meta(html, "description") ?? "",
    imageUrl: meta(html, "og:image"),
    html: absolutize(mainBody(html), base),
    url,
    updatedAt: meta(html, "article:modified_time"),
  };
}

interface WPItem {
  id: number;
  link: string;
  date_gmt?: string;
  modified_gmt?: string;
  title: { rendered: string };
  excerpt?: { rendered: string };
  content: { rendered: string };
  _embedded?: { "wp:featuredmedia"?: { source_url: string }[] };
}

// ---------------------------------------------------------------------------
// Home

export async function fetchHome(base: string, platform: Platform): Promise<HomeContent> {
  const res = await fetch(base, { headers: UA });
  const html = res.ok ? await res.text() : "";
  const hero = {
    title: meta(html, "og:title") ?? "Horizon Community Church",
    subtitle: meta(html, "og:description") ?? "Sundays at 9:30 & 11:00 AM in Tualatin",
    imageUrl: meta(html, "og:image"),
    url: base,
  };

  let announcements: Announcement[] = [];
  if (platform === "wordpress") {
    const r = await fetch(`${base}/wp-json/wp/v2/posts?per_page=10&_embed=1`, { headers: UA });
    if (r.ok) {
      const posts = (await r.json()) as WPItem[];
      announcements = posts.map((p) => ({
        id: String(p.id),
        title: stripTags(p.title.rendered),
        summary: stripTags(p.excerpt?.rendered ?? "").slice(0, 200),
        imageUrl: p._embedded?.["wp:featuredmedia"]?.[0]?.source_url ?? null,
        url: p.link,
        publishedAt: p.date_gmt ? `${p.date_gmt}Z` : null,
      }));
    }
  } else if (platform === "squarespace") {
    const r = await fetch(`${base}/blog?format=json`, { headers: UA });
    if (r.ok) {
      const j = (await r.json()) as { items?: { id: string; title: string; excerpt?: string; assetUrl?: string; fullUrl: string; publishOn?: number }[] };
      announcements = (j.items ?? []).slice(0, 10).map((i) => ({
        id: i.id,
        title: i.title,
        summary: stripTags(i.excerpt ?? "").slice(0, 200),
        imageUrl: i.assetUrl ?? null,
        url: `${base}${i.fullUrl}`,
        publishedAt: i.publishOn ? new Date(i.publishOn).toISOString() : null,
      }));
    }
  } else {
    // Fall back to an RSS feed if one is advertised in <head>.
    const feed = html.match(/<link[^>]+type=["']application\/rss\+xml["'][^>]*href=["']([^"']+)["']/i)?.[1];
    if (feed) {
      const r = await fetch(new URL(feed, base).toString(), { headers: UA });
      if (r.ok) {
        announcements = parseRss(await r.text()).slice(0, 10).map((i) => ({
          id: i.guid,
          title: i.title,
          summary: i.summary.slice(0, 200),
          imageUrl: i.imageUrl,
          url: i.link,
          publishedAt: i.publishedAt,
        }));
      }
    }
  }

  return {
    hero,
    announcements,
    pages: WEBSITE_PAGES.map(({ slug, title }) => ({ slug, title })),
    source: platform,
  };
}

// ---------------------------------------------------------------------------
// RSS (website feed + Planning Center Publishing podcast feed)

export interface FeedItem {
  guid: string;
  title: string;
  summary: string;
  link: string;
  publishedAt: string | null;
  imageUrl: string | null;
  audioUrl: string | null;
  durationSeconds: number | null;
  speaker: string | null;
}

function tag(xml: string, name: string): string | null {
  const m = xml.match(new RegExp(`<${name}(?:\\s[^>]*)?>([\\s\\S]*?)</${name}>`, "i"));
  if (!m) return null;
  return m[1]!.replace(/^<!\[CDATA\[|\]\]>$/g, "").trim();
}

function attr(xml: string, name: string, attribute: string): string | null {
  const m = xml.match(new RegExp(`<${name}[^>]*\\s${attribute}=["']([^"']+)["']`, "i"));
  return m ? decodeEntities(m[1]!) : null;
}

export function parseDuration(s: string | null): number | null {
  if (!s) return null;
  const parts = s.split(":").map(Number);
  if (parts.some(Number.isNaN)) return null;
  return parts.reduce((acc, p) => acc * 60 + p, 0);
}

export function parseRss(xml: string): FeedItem[] {
  const channelImage = attr(xml, "itunes:image", "href");
  return [...xml.matchAll(/<item[\s>][\s\S]*?<\/item>/gi)].map((m) => {
    const item = m[0];
    const pub = tag(item, "pubDate");
    const link = tag(item, "link") ?? "";
    return {
      guid: tag(item, "guid") ?? link,
      title: stripTags(tag(item, "title") ?? ""),
      summary: stripTags(tag(item, "itunes:summary") ?? tag(item, "description") ?? ""),
      link,
      publishedAt: pub ? new Date(pub).toISOString() : null,
      imageUrl: attr(item, "itunes:image", "href") ?? attr(item, "media:content", "url") ?? channelImage,
      audioUrl: attr(item, "enclosure", "url"),
      durationSeconds: parseDuration(tag(item, "itunes:duration")),
      speaker: tag(item, "itunes:author"),
    };
  });
}

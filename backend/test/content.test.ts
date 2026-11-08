import { test } from "node:test";
import assert from "node:assert/strict";
import { mainBody, meta, parseDuration, parseRss, stripTags } from "../src/content.ts";

const rss = `<?xml version="1.0"?><rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel>
<itunes:image href="https://img/channel.png"/>
<item><title><![CDATA[Hope &amp; Healing]]></title><link>https://cc/episodes/1</link><guid>ep-1</guid>
<pubDate>Sun, 02 Nov 2026 17:30:00 +0000</pubDate><itunes:author>Pastor Sam</itunes:author>
<itunes:duration>41:05</itunes:duration><enclosure url="https://audio/1.mp3" type="audio/mpeg" length="1"/>
<description>&lt;p&gt;Part 3&lt;/p&gt;</description></item>
<item><title>Second</title><guid>ep-2</guid><itunes:image href="https://img/2.png"/><itunes:duration>3600</itunes:duration></item>
</channel></rss>`;

test("parseRss reads podcast episodes", () => {
  const items = parseRss(rss);
  assert.equal(items.length, 2);
  assert.equal(items[0]!.title, "Hope & Healing");
  assert.equal(items[0]!.audioUrl, "https://audio/1.mp3");
  assert.equal(items[0]!.durationSeconds, 41 * 60 + 5);
  assert.equal(items[0]!.speaker, "Pastor Sam");
  assert.equal(items[0]!.imageUrl, "https://img/channel.png");
  assert.equal(items[0]!.publishedAt, "2026-11-02T17:30:00.000Z");
  assert.equal(items[1]!.imageUrl, "https://img/2.png");
  assert.equal(items[1]!.durationSeconds, 3600);
});

test("parseDuration", () => {
  assert.equal(parseDuration("1:02:03"), 3723);
  assert.equal(parseDuration(null), null);
  assert.equal(parseDuration("abc"), null);
});

test("meta reads Open Graph tags in either attribute order", () => {
  assert.equal(meta(`<meta property="og:title" content="Horizon">`, "og:title"), "Horizon");
  assert.equal(meta(`<meta content="Desc &amp; more" name="description">`, "description"), "Desc & more");
});

test("mainBody strips chrome and scripts", () => {
  const html = `<body><header>Menu</header><main><h1>About</h1><script>x()</script><p onclick="bad()">Hi</p></main><footer>F</footer></body>`;
  const body = mainBody(html);
  assert.ok(body.includes("<h1>About</h1>"));
  assert.ok(!body.includes("script"));
  assert.ok(!body.includes("onclick"));
  assert.equal(stripTags(body), "About Hi");
});

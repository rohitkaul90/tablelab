// deno test --allow-read supabase/functions/scrape-tournaments/
//
// Regression guard for the PokerNews calendar parser. The fixture is real markup
// trimmed from the live page on 2026-10-26, the day the weekly cron alerted
// "Scraper returned 0 tournaments": PokerNews had added data-gtm-id="…" to every
// series row and the old exact-string split on '<tr class="parent">' matched nothing.
import { assertEquals, assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { COUNTRY_MAP, PARENT_ROW_RE, parseHtml } from "./parse.ts";

const FIXTURE = Deno.readTextFileSync(
  new URL("./fixtures/pokernews-rows-2026-10-26.html", import.meta.url),
);
const URL_ = "https://www.pokernews.com/poker-tournaments/?df=1&dt=2&page=1";

Deno.test("2026-10-26 markup (data-gtm-id on the row) parses every series row", () => {
  const rows = parseHtml(FIXTURE, URL_);
  assertEquals(rows.length, 3);

  const [fr, ee, us] = rows;
  assertEquals(fr.name, "Championnat de France de Poker");
  assertEquals(fr.venue, "Pasino Grand Aix en Provence, Aix-en-Provence");
  assertEquals(fr.city, "Aix-en-Provence");
  assertEquals(fr.country, "France");
  assertEquals(fr.start_date, "2026-10-13");
  assertEquals(fr.end_date, "2026-10-26");
  assertEquals(fr.buy_in, null); // series rows carry no buy-in cell
  assertEquals(fr.source, "pokernews");
  assertEquals(fr.source_url, URL_);

  // Venue wrapped in an <a> (the link is stripped), Estonia newly mapped.
  assertEquals(ee.name, "European Mixed Poker Championship - EMPC 2026");
  assertEquals(ee.venue, "Olympic Park Casino, Tallinn");
  assertEquals(ee.city, "Tallinn");
  assertEquals(ee.country, "Estonia");

  assertEquals(us.name, "RunGood Poker Series - RGPS Golden Expedition Jacksonville");
  assertEquals(us.country, "USA");
  assertEquals(us.start_date, "2026-10-21");
  assertEquals(us.end_date, "2026-11-01");
});

Deno.test("legacy bare <tr class=\"parent\"> markup still parses (a PokerNews revert can't re-break it)", () => {
  const legacy = FIXTURE.replace(/ data-gtm-id="[^"]*"/g, "");
  assert(!legacy.includes('data-gtm-id="')); // the fixture header comment still names the attribute
  const rows = parseHtml(legacy, URL_);
  assertEquals(rows.map((r) => r.country), ["France", "Estonia", "USA"]);
});

Deno.test("row regex is attribute-tolerant but class-exact", () => {
  assert(PARENT_ROW_RE.test('<tr class="parent">'));
  assert(PARENT_ROW_RE.test('<tr class="parent" data-gtm-id="x">'));
  assert(PARENT_ROW_RE.test('<tr class="parent highlighted" data-x="1">'));
  assert(!PARENT_ROW_RE.test('<tr class="parentx">'));
  assert(!PARENT_ROW_RE.test('<tr class="child">'));
  assert(!PARENT_ROW_RE.test("<tr>"));
});

Deno.test("a page with no series rows yields no tournaments (the alert path)", () => {
  assertEquals(parseHtml("<table><tr><td>nothing</td></tr></table>", URL_), []);
});

Deno.test("unmapped country code drops the row; mapped Baltic codes keep it", () => {
  const zz = FIXTURE.replace("flags/fr.svg", "flags/zz.svg");
  assertEquals(parseHtml(zz, URL_).length, 2);
  for (const code of ["ee", "lt", "lv", "me", "mc"]) assert(code in COUNTRY_MAP, code);
});

// Pure parser for the PokerNews tournament calendar — kept free of Deno.serve /
// Supabase so parse.test.ts can import it directly (same split as
// analyze-hand/prompt.ts). Deploying the function ships this file too.

// ── Country code → display name ───────────────────────────────────────────────

export const COUNTRY_MAP: Record<string, string> = {
  us: 'USA', gb: 'UK', ca: 'Canada', es: 'Spain', de: 'Germany',
  fr: 'France', mt: 'Malta', au: 'Australia', cz: 'Czech Republic',
  at: 'Austria', be: 'Belgium', cy: 'Cyprus', hr: 'Croatia',
  dk: 'Denmark', fi: 'Finland', gr: 'Greece', hu: 'Hungary',
  ie: 'Ireland', it: 'Italy', lu: 'Luxembourg', nl: 'Netherlands',
  no: 'Norway', pl: 'Poland', pt: 'Portugal', ro: 'Romania',
  sk: 'Slovakia', si: 'Slovenia', se: 'Sweden', ch: 'Switzerland',
  tr: 'Turkey', ua: 'Ukraine', ru: 'Russia', ba: 'Bosnia',
  rs: 'Serbia', bg: 'Bulgaria', br: 'Brazil', mx: 'Mexico',
  ar: 'Argentina', co: 'Colombia', pe: 'Peru', cl: 'Chile',
  pa: 'Panama', cr: 'Costa Rica', do: 'Dominican Republic',
  bs: 'Bahamas', jm: 'Jamaica', bb: 'Barbados',
  hk: 'Hong Kong', jp: 'Japan', kr: 'South Korea', cn: 'China',
  in: 'India', th: 'Thailand', ph: 'Philippines', sg: 'Singapore',
  my: 'Malaysia', id: 'Indonesia', vn: 'Vietnam', tw: 'Taiwan',
  mo: 'Macau', nz: 'New Zealand', za: 'South Africa',
  ma: 'Morocco', eg: 'Egypt', il: 'Israel', ae: 'UAE',
  ee: 'Estonia', lt: 'Lithuania', lv: 'Latvia', me: 'Montenegro',
  mc: 'Monaco', ge: 'Georgia', kh: 'Cambodia',
}

// ── Helpers ───────────────────────────────────────────────────────────────────

export function toMySqlDays(date: Date): number {
  const y = date.getFullYear()
  const m = date.getMonth() + 1
  const d = date.getDate()
  const daysToYearStart =
    y * 365 + Math.floor(y / 4) - Math.floor(y / 100) + Math.floor(y / 400)
  const isLeap = (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0
  const monthDays = [0, 31, isLeap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  let dayOfYear = d
  for (let i = 1; i < m; i++) dayOfYear += monthDays[i]
  return daysToYearStart + dayOfYear
}

function isValidDate(s: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return false
  const [y, m, d] = s.split('-').map(Number)
  return y > 1900 && m >= 1 && m <= 12 && d >= 1 && d <= 31
}

function parseBuyIn(raw: string): { amount: number | null; currency: string } {
  const t = raw.trim()
  if (!t) return { amount: null, currency: 'USD' }
  let currency = 'USD'
  if (/CA\$|C\$/i.test(t)) currency = 'CAD'
  else if (t.includes('€')) currency = 'EUR'
  else if (t.includes('£')) currency = 'GBP'
  else if (t.includes('$')) currency = 'USD'
  else return { amount: null, currency: 'USD' }
  const nums = t.replace(/,/g, '').match(/\d+(?:\.\d+)?/g)
  if (!nums) return { amount: null, currency }
  const amount = Math.max(...nums.map(Number))
  return { amount: isFinite(amount) ? amount : null, currency }
}

function inferSeries(name: string): string | null {
  const u = name.toUpperCase()
  if (u.includes('WSOP CIRCUIT') || u.includes('WSOPC')) return 'WSOP Circuit'
  if (u.includes('WSOP')) return 'WSOP'
  if (/\bWPT\b/.test(u)) return 'WPT'
  if (/\bEPT\b/.test(u)) return 'EPT'
  if (u.includes('UKIPT')) return 'UKIPT'
  if (u.includes('SCOOP') || u.includes('WCOOP') || u.includes('MICOOP')) return 'PokerStars'
  if (/\bMSPT\b/.test(u)) return 'MSPT'
  if (u.includes('HEARTLAND') || /\bHPT\b/.test(u)) return 'HPT'
  return null
}

function stripTags(html: string): string {
  return html.replace(/<[^>]+>/g, '').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&#039;/g, "'").replace(/&quot;/g, '"').trim()
}

const SKIP_KEYWORDS = ['satellite', 'qualifier', 'freeroll']
function shouldSkip(name: string): boolean {
  const lower = name.toLowerCase()
  return SKIP_KEYWORDS.some(k => lower.includes(k))
}

// ── HTML parser (no WASM — pure string matching) ──────────────────────────────

/** Matches a series row open tag, with or without extra attributes. */
export const PARENT_ROW_RE = /<tr\s+class="parent(?:\s[^"]*)?"[^>]*>/i

export interface TournamentRow {
  name: string
  venue: string
  city: string
  country: string
  start_date: string
  end_date: string | null
  buy_in: number | null
  currency: string
  series: string | null
  source: string
  source_url: string
}

export function parseHtml(html: string, pageUrl: string): TournamentRow[] {
  const results: TournamentRow[] = []

  // Split on parent-row boundaries. Attribute-tolerant: on 2026-10-26 PokerNews
  // added data-gtm-id="…" to every series row (<tr class="parent" data-gtm-id="…">)
  // and the old exact-string split parsed 0 rows → false "HTML changed" alert.
  const segments = html.split(PARENT_ROW_RE)
  // First segment is before the table; skip it
  for (let i = 1; i < segments.length; i++) {
    const seg = segments[i]
    const rowEnd = seg.indexOf('</tr>')
    const row = rowEnd >= 0 ? seg.slice(0, rowEnd) : seg

    // ── Name ─────────────────────────────────────────────────────────────────
    const titleMatch = row.match(/<td[^>]*class="[^"]*title[^"]*"[^>]*>([\s\S]*?)<\/td>/i)
    if (!titleMatch) continue
    const titleHtml = titleMatch[1]

    const spanMatch = titleHtml.match(/<span[^>]*>([\s\S]*?)<\/span>/i)
    const venueRaw = spanMatch ? spanMatch[1] : ''
    const venueText = stripTags(venueRaw)
    const name = stripTags(titleHtml.replace(spanMatch ? spanMatch[0] : '', '')).replace(/\s+/g, ' ').trim()
    if (!name || shouldSkip(name)) continue

    // ── Venue / city ──────────────────────────────────────────────────────────
    // Format: "Venue Name, City, REGION"
    const venueParts = venueText.split(',').map(s => s.trim()).filter(Boolean)
    const venue = venueParts.length >= 2
      ? venueParts.slice(0, -1).join(', ')
      : venueText
    const city = venueParts.length >= 2
      ? venueParts[venueParts.length - 2]
      : ''

    // ── Country ───────────────────────────────────────────────────────────────
    const flagMatch = row.match(/\/img\/flags\/([a-z]{2})\.svg/i)
    const countryCode = flagMatch?.[1]?.toLowerCase() ?? ''
    const country = COUNTRY_MAP[countryCode] ?? ''
    if (!country) continue

    // ── Dates ─────────────────────────────────────────────────────────────────
    const dateCells = [...row.matchAll(/<td[^>]*class="[^"]*date[^"]*"[^>]*>([\s\S]*?)<\/td>/gi)]
    const startDate = dateCells[0] ? stripTags(dateCells[0][1]) : ''
    const endDateRaw = dateCells[1] ? stripTags(dateCells[1][1]) : ''
    if (!startDate || !isValidDate(startDate)) continue

    // ── Buy-in ────────────────────────────────────────────────────────────────
    const buyInMatch = row.match(/<td[^>]*class="[^"]*nr[^"]*"[^>]*>([\s\S]*?)<\/td>/i)
    const { amount: buyIn, currency } = parseBuyIn(
      buyInMatch ? stripTags(buyInMatch[1]) : '',
    )

    results.push({
      name,
      venue: venue || name,
      city: city || '',
      country,
      start_date: startDate,
      end_date: isValidDate(endDateRaw) ? endDateRaw : null,
      buy_in: buyIn,
      currency,
      series: inferSeries(name),
      source: 'pokernews',
      source_url: pageUrl,
    })
  }

  return results
}

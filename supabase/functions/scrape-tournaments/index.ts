import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { reportError } from '../_shared/alert.ts'

// ── Country code → display name ───────────────────────────────────────────────

const COUNTRY_MAP: Record<string, string> = {
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
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function toMySqlDays(date: Date): number {
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

interface TournamentRow {
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

function parseHtml(html: string, pageUrl: string): TournamentRow[] {
  const results: TournamentRow[] = []

  // Split on parent-row boundaries
  const segments = html.split('<tr class="parent">')
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

// ── Fetch one page ────────────────────────────────────────────────────────────

async function fetchPage(page: number, df: number, dt: number): Promise<TournamentRow[]> {
  const url =
    `https://www.pokernews.com/poker-tournaments/?df=${df}&dt=${dt}&page=${page}`
  const res = await fetch(url, {
    headers: {
      'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124 Safari/537.36',
      Accept: 'text/html',
    },
  })
  if (!res.ok) throw new Error(`HTTP ${res.status} on page ${page}`)
  const html = await res.text()
  return parseHtml(html, url)
}

// ── Entry point ───────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  const auth = req.headers.get('Authorization')
  const secret = Deno.env.get('SCRAPE_SECRET')
  if (!secret || auth !== `Bearer ${secret}`) {
    return new Response('Unauthorized', { status: 401 })
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )

  const today = new Date()
  const twoYearsOut = new Date(today)
  twoYearsOut.setFullYear(twoYearsOut.getFullYear() + 2)

  const df = toMySqlDays(today)
  const dt = toMySqlDays(twoYearsOut)

  const allRows: TournamentRow[] = []
  const errors: string[] = []

  for (let page = 1; page <= 20; page++) {
    try {
      const rows = await fetchPage(page, df, dt)
      if (rows.length === 0) break
      allRows.push(...rows)
      await new Promise(r => setTimeout(r, 400))
    } catch (err) {
      errors.push(`Page ${page}: ${err}`)
      break
    }
  }

  if (allRows.length === 0) {
    const msg = errors.length
      ? `Scraper failed: ${errors.join('; ')}`
      : 'Scraper returned 0 tournaments — PokerNews HTML may have changed'
    console.error(msg)
    await reportError('scrape-tournaments', msg)
    return new Response(JSON.stringify({ error: msg }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  // Deduplicate by (name, start_date) — same tournament can appear on multiple pages
  const seen = new Map<string, TournamentRow>()
  for (const row of allRows) seen.set(`${row.name}|${row.start_date}`, row)
  const uniqueRows = [...seen.values()]

  const { error: upsertError } = await supabase
    .from('tournament_listings')
    .upsert(uniqueRows, { onConflict: 'name,start_date' })

  if (upsertError) {
    console.error('Upsert failed:', upsertError.message)
    await reportError('scrape-tournaments', `tournament_listings upsert failed: ${upsertError.message}`)
    return new Response(JSON.stringify({ error: upsertError.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  console.log(`Scraped and upserted ${uniqueRows.length} tournaments (${allRows.length} raw)`)
  return new Response(
    JSON.stringify({ scraped: uniqueRows.length, errors }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  )
})

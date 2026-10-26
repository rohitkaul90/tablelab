import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { reportError } from '../_shared/alert.ts'
import { parseHtml, toMySqlDays, type TournamentRow } from './parse.ts'

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

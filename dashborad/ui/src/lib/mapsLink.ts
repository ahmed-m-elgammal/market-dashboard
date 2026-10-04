/**
 * Google Maps link -> coordinates. PURE CLIENT SIDE, NO NETWORK.
 *
 * WHY THIS IS NOT AN EDGE FUNCTION
 *   It was written as one first, ported from apps/admin's Next.js route, and then
 *   reversed. The reason the Next.js version needs a server is that it MINES
 *   GOOGLE'S HTML — `APP_INITIALIZATION_STATE`, `staticmap` centres, `og:image` —
 *   and no browser can read that, because google.com sends no CORS headers.
 *
 *   But the coordinate never needed to come out of the HTML. It is already in the
 *   string the operator pasted:
 *
 *     https://www.google.com/maps/place/Name/@30.0444,31.2357,17z/...
 *     https://www.google.com/maps/place/Name/data=!4m8!3m7!3d30.0444!4d31.2357
 *     https://www.google.com/maps?q=30.0444,31.2357
 *     https://www.google.com/maps/search/?api=1&query=30.0444,31.2357
 *
 *   Reading text that was pasted in needs no server. So: no Edge Function action,
 *   no outbound third-party request, no SSRF allowlist, no rate limit, and no
 *   audit row for what is a regex over a string. It resolves the instant the
 *   operator presses the button, and works offline.
 *
* WHAT A FULL PLACE LINK DOES CARRY
 *
 *   Correcting an earlier claim of mine: it DOES carry the business name. Google
 *   puts it in the path slug —
 *   `/place/%D9%85%D8%B7%D8%B9%D9%85+%D8%AD%D8%B6%D8%B1%D9%85%D9%88%D8%AA.../` decodes
 *   to the restaurant's name — and it carries the place's CID as `!1s0xHEX:0xHEX`.
 *   So a full link gives a name to prefill and a stable identifier to record, on
 *   top of the coordinates.
 *
 *   A SHORT link carries none of that: it is all behind the redirect.
 *
 * WHAT IT DELIBERATELY DOES NOT DO
 *
 *   It does not resolve a maps.app.goo.gl short link. That needs the redirect to
 *   be followed and its target read, which a browser cannot do cross-origin —
 *   the redirect comes back opaque. This is the one case that genuinely needs a
 *   server, and rather than ship a server for it the parser recognises the short
 *   form and asks for the full link, which is what Google's own "Copy link"
 *   produces.
 *
 *   It does NOT support Plus Codes / Open Location Codes (e.g.
 *   `8FVC9G8F+5W Cairo`). This was written and then cut. Plus code decoding is a
 *   progressive-division algorithm, a short code resolves to a 20km cell, and a
 *   cell centre is a confidently-wrong pin rather than an error. Since the input
 *   here is a pasted Maps LINK, a plus code that reaches this function is
 *   something the operator pasted by mistake, and "no coordinates, paste the
 *   link" is the honest answer. Deliberately not attempted rather than attempted
 *   and shipped untested — the whole point of the precision rule below is that a
 *   wrong pin is worse than no pin.
 *
 *   It does not extract a PHONE number, street address, hours or rating. None of
 *   those are in the URL. Google Places API is the only source, and it is a
 *   separate billing-enabled decision.
 *
* THE ONE REAL HAZARD, AND HOW IT IS HANDLED
 *   A place URL carries MORE THAN ONE coordinate pair and they disagree.
 *   Measured on a real link: the `@lat,lng` pair and the `!3d/!4d` pair were
 *   **199 metres apart**, both at 7 decimal places. `!8m2!3d30.0!4d31.0` is the
 *   VIEWPORT centre and is routinely rounded to a bare `0`, so taking the first
 *   match — or the rounded one — drops the pin in the desert.
 *
 *   So every pair is collected and the MOST PRECISE wins, with ties broken
 *   toward the `!3d/!4d` place pin over the `@lat,lng` viewport. That rule alone
 *   is what makes this safe, and it is what the tests below pin.
 *
 *   A proximity check between the top two candidates was written and then
 *   REMOVED. It looked prudent and earned nothing: when two candidates are close
 *   the operator cannot tell them apart from a form either, so the flag would
 *   have produced a choice they would make arbitrarily — exactly what the parser
 *   already did. It also fired on the 199m case above, where both candidates are
 *   the same restaurant and surfacing a "conflict" would be noise. The one
 *   genuinely dangerous case — a rounded viewport beating a precise pin — is
 *   fully handled by precision scoring, and nothing else needs a warning.
 */

/** How a pair was recognised. Surfaced so the UI can be honest with the operator. */
export type MapsLinkSource =
  | 'data_pair' // the !3dLAT!4dLNG place pin — the most accurate
  | 'at_pair' // the @lat,lng form
  | 'query_param'; // ?q= / ?query= / ?ll= / ?api=1&query=

export interface ParsedCoordinates {
  lat: number;
  lng: number;
  source: MapsLinkSource;
  /**
   * Business name from the `/place/<slug>/` segment, decoded and cleaned.
   *
   * A PREFILL, not an authority. Google appends a category to the slug
   * ("Foo Restaurant") and localises it, so this is offered to the operator to
   * accept or correct — never written straight to `name_ar` / `name_en`.
   */
  nameHint: string | null;
  /**
   * The place's CID, `0xHEX:0xHEX`. Google's stable identifier for the place,
   * and the only part of the link that survives a rebrand. Worth recording so a
   * later lookup does not depend on a name or an address that may change.
   */
  placeId: string | null;
}

/**
 * Every Unicode bidi control, as explicit escapes.
 *
 * Written as \uXXXX rather than as literal invisible characters: an invisible
 * character in source is unreviewable — a reader cannot see it, a diff does not
 * show it, and nobody notices when one is missed. This exact list exists because
 * the first attempt pasted LRM/RLM/ALM literally and then let a real link's
 * U+202D RTL OVERRIDE through into the business name.
 *
 *   U+200E LRM   U+200F RLM   U+061C ALM
 *   U+202A LRE   U+202B RLE   U+202C PDF   U+202D LRO   U+202E RLO
 *   U+2066 LRI   U+2067 RLI   U+2068 FSI   U+2069 PDI
 */
const BIDI_CONTROLS = /[\u200E\u200F\u061C\u202A-\u202E\u2066-\u2069]/g;

/**
 * The `/place/<slug>/` segment, decoded.
 *
 * Google writes the business name into the path, percent-encoded, with `+` for
 * spaces and wrapped in bidi controls for RTL names. Those controls are stripped
 * because they are invisible in a text field but corrupt string comparison and
 * search — a name ending in U+202D will never equal itself again.
 *
 * The slug also carries a trailing category ("-Cafe-Restaurant") and sometimes a
 * duplicate name after an em-dash. Neither is reliably separable from the name
 * itself, so nothing beyond whitespace and bidi marks is stripped — the operator
 * confirms the result rather than the parser guessing at it.
 */
function nameFromSlug(pathname: string): string | null {
  const m = pathname.match(/\/place\/([^/]+)/);
  if (!m || !m[1]) return null;

  let decoded: string;
  try {
    decoded = decodeURIComponent(m[1]);
  } catch {
    // A malformed escape is not worth failing the whole parse over — the
    // coordinates are still good.
    return null;
  }

  const cleaned = decoded.replace(/\+/g, ' ').replace(BIDI_CONTROLS, '').replace(/\s+/g, ' ').trim();

  return cleaned === '' ? null : cleaned;
}

/** `!1s0xHEX:0xHEX` — Google's stable place identifier. */
function placeIdFromPath(haystack: string): string | null {
  const m = haystack.match(/!1s(0x[0-9a-f]+:0x[0-9a-f]+)/i);
  return m && m[1] ? m[1] : null;
}

export type ParseFailure =
  | 'empty'
  | 'not_a_url'
  | 'not_google_maps'
  | 'short_link'
  | 'no_coordinates';

export class MapsLinkParseError extends Error {
  readonly code: ParseFailure;

  // An explicit field rather than a constructor parameter property: it keeps
  // this module runnable under `node --experimental-strip-types`, which is how
  // scripts/check-maps-link.ts exercises it without a bundler in the loop. The
  // rest of the app uses parameter properties freely under Vite; a pure
  // function module with no runtime dependencies is worth keeping portable.
  constructor(code: ParseFailure) {
    super(code);
    this.name = 'MapsLinkParseError';
    this.code = code;
  }
}

/**
 * Hosts that legitimately carry a Maps place link.
 *
 * The country domains are included because an operator working in Egypt can
 * easily land on `google.com.eg` from a shared link, and refusing it would be
 * correct-but-useless. Membership is an exact match on a small set — NOT a suffix
 * test, which would accept `google.com.attacker.net`.
 */
const MAPS_HOSTS = new Set([
  'google.com',
  'www.google.com',
  'maps.google.com',
  'www.maps.google.com',
  'google.com.eg',
  'www.google.com.eg',
  'google.co.uk',
  'www.google.co.uk',
]);

/** The short-link host. Recognised only so it can be EXPLAINED, never resolved. */
const SHORT_LINK_HOSTS = new Set(['maps.app.goo.gl', 'goo.gl', 'www.goo.gl']);

interface Pair {
  lat: number;
  lng: number;
  source: MapsLinkSource;
}

/**
 * Decimal places in a number.
 *
 * The signal that separates a place pin from a rounded viewport centre: a pin
 * carries 4+ decimals, a viewport routinely carries 1 or none. Counting rather
 * than testing a fixed threshold means the rule survives a place that genuinely
 * sits on a round coordinate.
 */
function precision(n: number): number {
  const s = String(n);
  const dot = s.indexOf('.');
  return dot === -1 ? 0 : s.length - dot - 1;
}

/**
 * Rank used only to break a precision tie.
 *
 * `!3d/!4d` is the place itself; `@lat,lng` is the viewport; a query param is
 * usually an explicit search. So on equal precision the data pair is preferred.
 */
const SOURCE_RANK: Record<MapsLinkSource, number> = {
  data_pair: 3,
  at_pair: 2,
  query_param: 1,
};

/**
 * The most precise pair wins; ties break toward the place pin.
 *
 * This single rule is what makes the whole thing safe. A place URL's other pair
 * is the viewport centre, which Google rounds — picking it puts the pin in the
 * desert. Precision in the decimal places is the signal, and SOURCE_RANK settles
 * the genuinely-equal case in favour of `!3d/!4d`, which is the place itself.
 */
function best(pairs: Pair[]): Pair | null {
  if (pairs.length === 0) return null;
  const score = (p: Pair) =>
    precision(p.lat) * 1000 + precision(p.lng) * 10 + SOURCE_RANK[p.source];
  return pairs.reduce((winner, candidate) =>
    score(candidate) > score(winner) ? candidate : winner,
  );
}

/** Lat/lng as decimals with a required fractional part — rejects `30` and `30,31`. */
const PAIR = /(-?\d{1,3}\.\d+)\s*,\s*(-?\d{1,3}\.\d+)/;

function inRange(lat: number, lng: number): boolean {
  return (
    Number.isFinite(lat) &&
    Number.isFinite(lng) &&
    lat >= -90 &&
    lat <= 90 &&
    lng >= -180 &&
    lng <= 180
  );
}

function collect(haystack: string, re: RegExp, source: MapsLinkSource): Pair[] {
  const out: Pair[] = [];
  const rx = new RegExp(re.source, 'g');
  for (let m = rx.exec(haystack); m !== null; m = rx.exec(haystack)) {
    const lat = Number(m[1]);
    const lng = Number(m[2]);
    if (inRange(lat, lng)) out.push({ lat, lng, source });
  }
  return out;
}

/**
 * `!3d30.0444!4d31.2357` — the place pin.
 *
 * Matched as an ADJACENT PAIR on purpose. `!3d` and `!4d` each appear many times
 * in a place URL, so two independent regexes could pair a latitude from one
 * object with a longitude from another and produce a confident wrong answer.
 * Adjacency is the only thing that makes them a pair.
 */
function dataPairs(haystack: string): Pair[] {
  return collect(haystack, /!3d(-?\d{1,3}\.\d+)!4d(-?\d{1,3}\.\d+)/, 'data_pair');
}

/** `@30.0444,31.2357` — the viewport centre, commonly followed by `,17z`. */
function atPairs(haystack: string): Pair[] {
  return collect(haystack, /@(-?\d{1,3}\.\d+),(-?\d{1,3}\.\d+)/, 'at_pair');
}

/** `?q=`, `?query=`, `?ll=`, plus the Places-style `?api=1&query=`. */
function queryPairs(url: URL): Pair[] {
  const out: Pair[] = [];
  for (const key of ['q', 'query', 'll', 'center', 'coords']) {
    const raw = url.searchParams.get(key);
    if (!raw) continue;
    const m = raw.match(PAIR);
    if (!m) continue;
    const lat = Number(m[1]);
    const lng = Number(m[2]);
    if (inRange(lat, lng)) out.push({ lat, lng, source: 'query_param' });
  }
  return out;
}

/**
 * Parse a pasted Maps link into coordinates.
 *
 * @throws {MapsLinkParseError} whose `code` separates the cases the UI must give
 * different advice for: a short link is fixable by the operator, a non-Google URL
 * means they pasted the wrong thing, and no-coordinates means the link was a
 * place page without a pin.
 */
export function parseGoogleMapsLink(input: string): ParsedCoordinates {
  const raw = (input ?? '').trim();
  if (raw === '') throw new MapsLinkParseError('empty');

  // Tolerate a protocol-less or scheme-less paste before URL parsing rejects it.
  const candidate = /^https?:\/\//i.test(raw) ? raw : `https://${raw.replace(/^\/+/, '')}`;

  let url: URL;
  try {
    url = new URL(candidate);
  } catch {
    throw new MapsLinkParseError('not_a_url');
  }

  const host = url.hostname.toLowerCase();

  if (SHORT_LINK_HOSTS.has(host)) {
    // The one case that genuinely needs a server, and the one an operator can fix
    // themselves. Said plainly instead of "no coordinates", because the advice
    // is different and actionable.
    throw new MapsLinkParseError('short_link');
  }

  if (!MAPS_HOSTS.has(host)) {
    throw new MapsLinkParseError('not_google_maps');
  }

  // Path AND query: a place URL carries its pin in the path (`/@lat,lng`), a
  // search URL in the query (`?q=`), and the place id and name in the path too.
  const haystack = `${url.pathname}${url.search}`;

  const pairs = [...dataPairs(haystack), ...atPairs(haystack), ...queryPairs(url)];
  const chosen = best(pairs);
  if (!chosen) throw new MapsLinkParseError('no_coordinates');


  return {
    lat: chosen.lat,
    lng: chosen.lng,
    source: chosen.source,
    nameHint: nameFromSlug(url.pathname),
    placeId: placeIdFromPath(haystack),
  };
}

/** Non-throwing form, for callers that would rather branch than catch. */
export function tryParseGoogleMapsLink(
  input: string,
): { ok: true; value: ParsedCoordinates } | { ok: false; error: MapsLinkParseError } {
  try {
    return { ok: true, value: parseGoogleMapsLink(input) };
  } catch (error) {
    if (error instanceof MapsLinkParseError) return { ok: false, error };
    throw error;
  }
}
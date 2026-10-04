/**
 * Reading a place out of text the operator pasted from Google Maps.
 *
 * SCOPE, HONESTLY STATED
 *
 * Coordinates are the thing that matters, and they come from the link, which
 * already works. Everything here is opportunistic: it fills the address and
 * phone when it recognises them and does nothing when it does not. No field
 * depends on it, and the operator reviews whatever lands before saving.
 *
 * WHY THE PASTE EXISTS AT ALL
 *
 * The link carries a name, coordinates and a CID. It does NOT carry the address
 * or phone, and neither does any free source I could find:
 *
 *   - the Maps page has no `tel:` link and no phone-shaped value in its
 *     34k-character APP_INITIALIZATION_STATE blob
 *   - OpenStreetMap `extratags` is null for the test place
 *   - an Overpass query for ANY phone within 60m returned 0 elements
 *
 * Google loads those after JavaScript runs. The operator is already looking at
 * them in the info panel when they copy the link, so pasting that text is faster
 * than typing 40 characters.
 *
 * WHY THERE ARE NO ARABIC WORD LISTS HERE
 *
 * An earlier version decided whether a line was an address by testing whether it
 * started with a street word, including Arabic ones. It failed on every Arabic
 * line, because the hand-typed literal in the source was one letter off
 * ("شروع" for "شارع") and so matched nothing — silently, since a regex that
 * matches nothing is not an error.
 *
 * Rather than maintain a vocabulary list that can be mistyped in a way tests
 * only catch if you happen to test that exact word, the rule is now LENIENT:
 * drop the lines that are obviously something else, and take what remains. The
 * precision that was being bought was not worth a class of silent failure, and
 * the operator is confirming the result anyway.
 */
import { pickPhone } from './phone.ts';

/**
 * Lines that are definitely not an address.
 *
 * These are the things Maps shows around the address that would be actively
 * wrong to paste into the field: a phone, a link, opening hours, a rating. Being
 * strict here matters more than being strict about real addresses, because a
 * review count saved as a street address is a data bug nobody notices for weeks.
 */
const NOT_ADDRESS: RegExp[] = [
  /https?:\/\//i, // any URL
  /\bwww\./i, // bare domain
  /^\s*\d{1,2}\s*[:：.]\s*\d{2}/, // a time, e.g. 11:00
  /[٠-٩]/, // Arabic-Indic digits, which the hours row uses
  /^\s*(?:open|closed|مفتوح|مغلق)\b/i, // status row
  /\b(?:reviews?|ratings?|تقييمات?|تقييم|تقييماً)\b/i, // rating row
  /[★☆]/, // stars
  /^\s*[\d\s.,()٫٬+-]+\s*$/, // only digits, separators and a leading plus: a phone or a count
];

/**
 * True when this line cannot be an address.
 *
 * Only digits-and-punctuation counts as a number here. A line of digits with
 * letters is a legitimate place name ("15th of May Street"), so it is allowed
 * through and judged on the rest.
 */
function isNotAddress(line: string): boolean {
  const trimmed = line.trim();
  if (trimmed === '') return true;

  // A line that contains a phone number is a label for one, not a street.
  // "Branch A: 01012345678" is four words and no comma, so a word count cannot
  // catch it, and a real address never carries a phone with it.
  if (pickPhone(trimmed) !== null) return true;

  return NOT_ADDRESS.some((re) => re.test(trimmed));
}

/** Comma shapes Maps uses: ASCII, Arabic, and the full-width form. */
const SEPARATOR = /\s*[,،、]\s*/;

/**
 * An address-ish line: has at least one comma-separated part, or several words.
 *
 * This is the only positive test, and it is deliberately weak. It is enough to
 * separate "شارع المساعيد، العريش" from "Open until 11 PM" without needing to
 * know a single word in any language.
 */
function looksLikeAddress(line: string): boolean {
  const parts = line.split(SEPARATOR).filter((p) => p.trim() !== '');
  if (parts.length >= 2) return true;

  // No comma, so it must be several words. The digit test is what stops
  // "Branch A: 01012345678" from being read as a street address: it has four
  // words, but it is a label followed by a number.
  const words = (parts[0] ?? '').trim().split(/\s+/).filter(Boolean);
  if (words.length < 3) return false;
  return !/^\d/.test(words[0]);
}

/**
 * Pull an address out of pasted Maps text, or null.
 *
 * Returns null rather than a guess. An address field holding an opening time is
 * worse than an empty one, because the operator has no reason to check a field
 * that looks filled.
 */
export function pickAddress(text: string): string | null {
  if (!text) return null;

  const lines = text
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => !isNotAddress(l));

  // Prefer the most specific line available: more parts means more of an
  // address, so a full "street, city, governorate, country" beats a bare city.
  const candidates = lines.filter(looksLikeAddress);
  if (candidates.length === 0) return null;

  const best = candidates.reduce((a, b) => {
    const parts = (s: string) => s.split(SEPARATOR).filter((p) => p.trim() !== '').length;
    return parts(b) > parts(a) ? b : a;
  });

  return best.length <= 200 ? best : null;
}

export interface PastedPlace {
  phone: string | null;
  address: string | null;
}

/**
 * Everything worth taking from one paste of the Maps info panel.
 *
 * The name is deliberately not guessed from here. The Maps link's own slug is
 * the better source and that path already works; reading a business name out of
 * an address is how "El Arish" ends up as a merchant's name.
 */
export function parsePastedPlace(text: string): PastedPlace {
  return {
    phone: pickPhone(text),
    address: pickAddress(text),
  };
}

/**
 * Egyptian mobile numbers, recognised from text a human pasted.
 *
 * WHY THIS IS NOT A LOOKUP
 *
 * I looked for the phone number of a real restaurant in every free dataset that
 * exists, and it is not there:
 *
 *   - the Maps place page: no `tel:` link, no phone-shaped value anywhere in
 *     its 34k-character APP_INITIALIZATION_STATE blob
 *   - OpenStreetMap `extratags`: null for that place
 *   - an Overpass query for ANY phone within 60m of the pin: 0 elements
 *
 * There is no free source to read a phone from. The one place the number
 * reliably exists is the business's own Maps info panel, which the operator can
 * see and copy — so this finds the number in what they paste.
 *
 * BUILT TO BE WRONG SAFELY
 *
 * Every rule below exists because the obvious version gave a wrong answer:
 *
 *   1. Digit boundaries. `1234567890` is an order id. With no boundary check it
 *      matched, because `1[0-2]` sits happily inside it.
 *   2. The trunk zero is REQUIRED in the local form. `1012345678` inside
 *      `#1234567890` is distinguishable from a real number only by that zero,
 *      so a bare 10-digit run is not accepted unless it is the entire input.
 *   3. Exactly 11 digits in text, or 10 when the input is only the number.
 *   4. More than one distinct number returns null. Guessing between two
 *      branches would attach the wrong vendor's number to a merchant, and a
 *      wrong number misdirects real orders. Null costs one typed field.
 *
 * The two-branch split is not stylistic: `+20 101 234 5678` has no trunk zero
 * while `010 1234 5678` must have one, and no single optional-prefix group can
 * express "required in one branch, forbidden in the other".
 */

/** Egyptian mobile operator codes: 010, 011, 012. */
const OPERATOR = String.raw`1[0-2]`;

/**
 * The 8 digits after the operator code.
 *
 * `[\s-]?` between EVERY pair rather than once in the middle, because the
 * separator lands in a different place depending on the prefix: in
 * `010 1234 5678` it falls after the trunk zero, but in `+20 101 234 5678` the
 * same text leaves the separator inside the body. A single optional separator
 * matched only one of those two.
 */
const BODY = String.raw`\d(?:[\s-]?\d){7}`;

/**
 * Local form — the trunk zero is mandatory.
 *
 * Named groups, and named uniquely per branch, because `(A)|(B)` numbers its
 * groups across the whole pattern: group 1 is always A's first group even when
 * B matched, so reading group 2 for the body produced garbage. The names say
 * which branch actually matched.
 */
const LOCAL = String.raw`0(?<lop>${OPERATOR})[\s-]?(?<lbody>${BODY})`;

/** International form — no trunk zero after the country code. */
const INTERNATIONAL = String.raw`\+?20[\s-]?(?<iop>${OPERATOR})[\s-]?(?<ibody>${BODY})`;

/** Not preceded by a digit: stops a match starting inside a longer number. */
const LEADING = String.raw`(?<!\d)`;

/** Not followed by a digit: stops a match ending mid-number. */
const TRAILING = String.raw`(?!\d)`;

const ANY = String.raw`(?:${INTERNATIONAL}|${LOCAL})`;

const IN_TEXT = new RegExp(LEADING + ANY + TRAILING, 'g');

/**
 * For input that IS a bare number, with nothing else in it.
 *
 * A whole-string match is what makes the no-trunk-zero local form safe: in free
 * text `1012345678` is indistinguishable from the tail of an order id, but as
 * the entire input there is nothing it could be a substring of.
 */
const WHOLE_STRING = new RegExp(
  String.raw`^\s*(?<hop>${OPERATOR})[\s-]?(?<hbody>${BODY})\s*$`,
);

function digitsOnly(s: string): string {
  return s.replace(/\D/g, '');
}

/** Operator + body from whichever branch matched, or null if neither did. */
function numberFrom(m: RegExpExecArray | null): string | null {
  const g = m?.groups;
  if (!g) return null;
  const operator = g.lop ?? g.iop ?? g.hop;
  const body = g.lbody ?? g.ibody ?? g.hbody;
  if (!operator || !body) return null;

  const digits = digitsOnly(operator + body);
  return digits.length === 10 ? digits : null;
}

/** Every distinct mobile in the text, in order. */
function candidatesIn(text: string): string[] {
  const found: string[] = [];

  IN_TEXT.lastIndex = 0;
  let m: RegExpExecArray | null;
  while ((m = IN_TEXT.exec(text)) !== null) {
    const digits = numberFrom(m);
    if (digits) found.push(digits);

    // Guarantee progress; a zero-width match would otherwise loop forever.
    if (m.index === IN_TEXT.lastIndex) IN_TEXT.lastIndex++;
  }

  if (found.length === 0) {
    const whole = numberFrom(WHOLE_STRING.exec(text));
    if (whole) found.push(whole);
  }

  // The same number written twice is still one number, so it is not ambiguous.
  return [...new Set(found)];
}

/**
 * The single unambiguous Egyptian mobile in this text, or null.
 *
 * Null is a real answer, not a failure: no mobile present, or more than one.
 */
export function pickPhone(text: string): string | null {
  if (!text) return null;
  const found = candidatesIn(text);
  return found.length === 1 ? found[0] : null;
}

/**
 * pickPhone, but keeps the country code when the text clearly had one.
 *
 * For display only — the form stores the local form and the API normalises on
 * write.
 */
export function pickPhoneLoose(text: string): string | null {
  if (!text) return null;

  const intl = text.match(
    new RegExp(String.raw`\+?20[\s-]?${OPERATOR}[\s-]?${BODY}`),
  );
  if (intl) return '20' + digitsOnly(intl[0]).replace(/^20/, '');
  return pickPhone(text);
}

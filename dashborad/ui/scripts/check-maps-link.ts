// Throwaway verification of src/lib/mapsLink.ts against real URL shapes.
// Run: node --experimental-strip-types scripts/check-maps-link.ts
import { parseGoogleMapsLink, MapsLinkParseError } from '../src/lib/mapsLink.ts';

const cases: [string, string][] = [
  // The REAL short link the operator supplied. Cannot be resolved client-side.
  ['REAL short link', 'https://maps.app.goo.gl/qZvViHmzCg77wGFF9'],
  // Its server-resolved target, pasted as the operator would after "Copy link".
  [
    'REAL resolved target',
    'https://www.google.com/maps/place/%D9%85%D8%B7%D8%B9%D9%85+%D8%AD%D8%B6%D8%B1%D9%85%D9%88%D8%AA+%D8%A7%D9%84%D8%B9%D8%B1%D9%8A%D8%B4%E2%80%AD/@31.1192138,33.7095813,334m/data=!3m1!1e3!4m6!3m5!1s0x14fc2b50a658755b:0x96013cc9d1f5991e!8m2!3d31.1198217!4d33.7115505!16s%2Fg%2F11j1m71k9l',
  ],
  // Rounded viewport must lose to the precise pair.
  [
    'rounded viewport vs place',
    'https://www.google.com/maps/place/El+Hamshi/@30.0444,31.2357,17z/data=!4m8!3m7!1s0x1!8m2!3d30.0!4d31.0!16s',
  ],
  ['viewport only, rounded', 'https://www.google.com/maps/place/Cafe/@30.0,31.0,17z'],
  ['place: data pair only', 'https://www.google.com/maps/place/Shop/data=!4m8!3m7!3d30.0444!4d31.2357!16s'],
  ['bare @ pair', 'https://www.google.com/maps/place/Cafe/@30.0500,31.2400,17z'],
  ['?q= param', 'https://www.google.com/maps?q=30.0444,31.2357'],
  ['?api=1&query=', 'https://www.google.com/maps/search/?api=1&query=30.0444,31.2357'],
  ['?ll= param', 'https://maps.google.com/?ll=30.0444,31.2357&z=17'],
  ['google.com.eg', 'https://www.google.com.eg/maps/place/X/@30.0123,31.4567,17z'],
  ['scheme-less paste', 'www.google.com/maps/place/X/@30.0123,31.4567,17z'],
  ['short link, goo.gl', 'https://goo.gl/abc'],
  ['place page, no pin', 'https://www.google.com/maps/place/Some+Place'],
  ['non-Google host', 'https://evil.com/maps/@30.0,31.0'],
  ['suffix-lookalike host', 'https://google.com.attacker.net/maps/@30.0,31.0'],
  ['empty', ''],
  ['garbage', 'not a url at all'],
  ['out-of-range lat', 'https://www.google.com/maps?q=999.0,31.0'],
];

for (const [name, input] of cases) {
  try {
    const r = parseGoogleMapsLink(input);
    console.log(`OK    ${name}`);
    console.log(`        pin     ${r.lat}, ${r.lng}  [${r.source}]`);
    console.log(`        name    ${r.nameHint ?? '—'}`);
    console.log(`        placeId ${r.placeId ?? '—'}`);
  } catch (e) {
    const code = e instanceof MapsLinkParseError ? e.code : `THREW ${String(e)}`;
    console.log(`ERR   ${name.padEnd(30)} -> ${code}`);
  }
}
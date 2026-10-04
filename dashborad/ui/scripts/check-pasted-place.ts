// Verification for pastedPlace.ts against text shaped like a real Maps
// info-panel copy.
// Run: node --experimental-strip-types scripts/check-pasted-place.ts
import { parsePastedPlace, pickAddress } from '../src/lib/pastedPlace.ts';

// What Maps shows under a place name, in the order it shows it.
const REAL_PANEL = `مطعم حضرموت العريش
شارع المساعيد، العريش، شمال سيناء، مصر
0100 123 4567
مفتوح الآن ⋅ الإغلاق 11:00 مساءً
4.5 ⭐ (128 تقييم)
https://maps.google.com/?cid=123`;

const ENGLISH_PANEL = `Hadoot Masri Restaurant
12 El Masaaed St, El Arish, North Sinai, Egypt
+20 101 234 5678
Open ⋅ Closes 11 PM
4.5 stars (128 reviews)
Website: hadoot.example.com`;

const cases: Array<[string, string, { phone: string | null; address: string | null }]> = [
  ['real Arabic panel', REAL_PANEL, { phone: '1001234567', address: 'شارع المساعيد، العريش، شمال سيناء، مصر' }],
  ['English panel', ENGLISH_PANEL, { phone: '1012345678', address: '12 El Masaaed St, El Arish, North Sinai, Egypt' }],
  ['phone only', '01012345678', { phone: '1012345678', address: null }],
  ['address only', 'شارع المساعيد، العريش', { phone: null, address: 'شارع المساعيد، العريش' }],
  [
    'two branches -> no phone',
    'Branch A: 01012345678\nBranch B: 01198765432',
    { phone: null, address: null },
  ],
  ['hours pasted by mistake', 'Open until 11:00 PM\n4.5 (128 reviews)', { phone: null, address: null }],
  ['website only', 'https://example.com\nwww.example.com', { phone: null, address: null }],
  ['empty', '', { phone: null, address: null }],
];

let failures = 0;
for (const [label, input, want] of cases) {
  const got = parsePastedPlace(input);
  const ok = got.phone === want.phone && got.address === want.address;
  if (!ok) failures++;
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}`);
  if (!ok) {
    console.log(`        got  phone=${got.phone} address=${JSON.stringify(got.address)}`);
    console.log(`        want phone=${want.phone} address=${JSON.stringify(want.address)}`);
  } else {
    console.log(`        phone=${got.phone}  address=${JSON.stringify(got.address)}`);
  }
}

// The address reader on its own, for the lines that must never be an address.
console.log('\n=== lines that must not become an address ===');
const rejects = [
  '4.5 stars',
  'Open ⋅ Closes 11 PM',
  'https://example.com',
  '01012345678',
  '(128 reviews)',
  '123 reviews',
  '★★★★☆',
];
for (const line of rejects) {
  const got = pickAddress(line);
  const ok = got === null;
  if (!ok) failures++;
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${JSON.stringify(line).padEnd(28)} -> ${JSON.stringify(got)}`);
}

console.log(`\n${failures === 0 ? 'all cases pass' : `${failures} FAILURES`}`);
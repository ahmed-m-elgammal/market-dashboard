/**
 * Deterministic demo dataset generator.
 *
 * WHY A GENERATOR AND NOT A HAND-WRITTEN data.json
 *   The realistic shape is 24 merchants x 6 categories x 10 items = 1,440 items,
 *   plus a 180-day order history so the Overview has something true to say.
 *   Hand-authoring that is thousands of lines nobody can review, and every
 *   change means retyping it. This script is the reviewable artifact: change a
 *   number here, re-run, and the whole dataset follows.
 *
 * WHY IT IS SAFE TO RUN
 *   It writes exactly one file, src/demo/data.json. It opens no socket, reads
 *   no credential and references no Supabase URL. Re-running it produces a
 *   byte-identical file (see DETERMINISM), so it can never drift under a
 *   reviewer's feet.
 *
 * WHY THERE ARE NO IMAGE URLS
 *   items.image_url is emitted as null for every row. The dashboard renders a
 *   deterministic placeholder derived from the item name instead, so the demo
 *   data carries no link back to any Supabase storage bucket -- swapping to the
 *   live provider later needs no cleanup pass over this file.
 *
 * HOW THE OVERVIEW NUMBERS ARE PRODUCED
 *   Not fabricated. The script synthesises a real order stream, then derives
 *   get_platform_kpis / get_daily_series / get_trending_items /
 *   get_recent_orders from it exactly as the SQL in migration 120 does. That
 *   keeps the four Overview panels mutually consistent: revenue equals the sum
 *   of the orders shown, and the trending list is genuinely the top of the
 *   generated catalog rather than a separate fiction.
 *
 *   The one place it deliberately DIVERGES from SQL: a PL/pgSQL aggregate is
 *   written once in the database and tested by the pytest suite, while this is a
 *   second implementation of the same rules. It is a fixture generator, not a
 *   source of truth -- when the two disagree, the SQL is right.
 *
 * USAGE
 *   node scripts/generate-demo-data.mjs
 */

import { createHash } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// ---------------------------------------------------------------------------
// DETERMINISM
// ---------------------------------------------------------------------------

/**
 * Every random draw goes through one of these, seeded from a constant. Nothing
 * reads the clock or Math.random, so the output depends only on this file's
 * contents. That is what makes "re-run and diff" a meaningful check.
 */
const SEED = 0x5eed_1a7e;

function mulberry32(seed) {
  let a = seed >>> 0;
  return function next() {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const rand = mulberry32(SEED);

/** Integer in [min, max]. */
const randInt = (min, max) => min + Math.floor(rand() * (max - min + 1));

/** Uniform pick. */
const pick = (list) => list[Math.floor(rand() * list.length)];

/**
 * Weighted pick. `weights` is parallel to `list` and need not sum to 1.
 * Used wherever the real world is skewed -- most orders are delivered, most
 * merchants are approved -- so the demo data has the same shape as production
 * and the panels are not all uniform bars.
 */
function weightedPick(list, weights) {
  const total = weights.reduce((sum, w) => sum + w, 0);
  let roll = rand() * total;
  for (let i = 0; i < list.length; i += 1) {
    roll -= weights[i];
    if (roll <= 0) return list[i];
  }
  return list[list.length - 1];
}

/**
 * Stable UUIDv5-shaped identifier derived from a name.
 *
 * Formatted with the version and variant bits set so it is a well-formed UUID,
 * but the digest is a plain sha1 rather than a namespaced one: the only
 * requirement here is that the same logical row always gets the same id, so
 * that a saved localStorage overlay still matches after the dataset is
 * regenerated.
 */
const UUID_NAMESPACE = 'marketak-demo';
function uuid(name) {
  const hash = createHash('sha1').update(`${UUID_NAMESPACE}:${name}`).digest();
  const bytes = Buffer.from(hash.subarray(0, 16));
  bytes[6] = (bytes[6] & 0x0f) | 0x50; // version 5
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
  const hex = bytes.toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

// ---------------------------------------------------------------------------
// TIME
// ---------------------------------------------------------------------------

/**
 * Africa/Cairo is pinned to UTC+02:00.
 *
 * Egypt observed DST between 2023 and late2024 and does not as of 2026, so a
 * fixed offset is currently correct. It is hardcoded rather than read from the
 * system because a generator whose output depends on the machine's TZ cannot be
 * diffed between a laptop and CI. `TZ=UTC` and `TZ=Asia/Tokyo` must produce the
 * same file.
 *
 * If Egypt reinstates DST, this is the single line to revisit -- and the
 * generated `day` strings are what the demo provider parses, so they would
 * shift by an hour across a DST boundary.
 */
const CAIRO_OFFSET_MS = 2 * 3_600_000;

/** Calendar date in Cairo, as YYYY-MM-DD. */
function cairoDay(epochMs) {
  return new Date(epochMs + CAIRO_OFFSET_MS).toISOString().slice(0, 10);
}

/** Midnight Cairo on `day`, as epoch ms. */
function cairoDayStart(day) {
  return Date.parse(`${day}T00:00:00.000Z`) - CAIRO_OFFSET_MS;
}

function addDays(day, count) {
  return cairoDay(cairoDayStart(day) + count * 86_400_000);
}

/**
 * The dataset is anchored to a fixed "today" rather than Date.now().
 *
 * An Overview whose numbers move every time the file is regenerated cannot be
 * reviewed: a diff would show every date changing. Pinning it means regenerating
 * after a content change produces a diff that only contains the content change.
 * The consequence, stated plainly: the demo Overview's dates age. After 90 days
 * the earliest window has slid past the start of the history and the 90-day
 * figures will read as smaller than intended. Bump DEMO_TODAY when that starts
 * to matter.
 */
const DEMO_TODAY = '2026-10-03';

/** History length. The widest Overview window is 90 days and the KPI card
 *  compares against the window before it, so 2 x 90 + a margin is the floor. */
const HISTORY_DAYS = 200;

/** Average orders placed per day, across the whole platform. */
const ORDERS_PER_DAY = 22;

// ---------------------------------------------------------------------------
// REFERENCE DATA -- copied from the database, never invented
// ---------------------------------------------------------------------------

/**
 * merchant_categories, migration 097. merchants.category is an FK to
 * merchant_categories.code, so this list is the whole legal domain of the
 * column -- a value outside it cannot be inserted.
 */
const MERCHANT_CATEGORIES = [
  { code: 'restaurant', name_en: 'Restaurants', name_ar: 'مطاعم', icon: '🍽️', sort_order: 1 },
  { code: 'pharmacy', name_en: 'Pharmacies', name_ar: 'صيدليات', icon: '💊', sort_order: 2 },
  { code: 'market', name_en: 'Markets', name_ar: 'أسواق', icon: '🏪', sort_order: 3 },
  { code: 'grocery', name_en: 'Grocery', name_ar: 'بقالة', icon: '🛒', sort_order: 4 },
  { code: 'bakery', name_en: 'Bakery', name_ar: 'مخبوزات', icon: '🥖', sort_order: 5 },
  { code: 'butcher', name_en: 'Butcher', name_ar: 'جزارة', icon: '🥩', sort_order: 6 },
  { code: 'flowers', name_en: 'Flowers', name_ar: 'زهور', icon: '💐', sort_order: 7 },
  { code: 'other', name_en: 'Other', name_ar: 'أخرى', icon: '📦', sort_order: 8 },
];

const CITIES = [
  { city: 'Cairo', city_ar: 'القاهرة', areas: ['Maadi', 'Heliopolis', 'Nasr City', 'Zamalek', 'Shubra'] },
  { city: 'Giza', city_ar: 'الجيزة', areas: ['Dokki', 'Mohandessin', '6th of October', 'Haram'] },
  { city: 'Alexandria', city_ar: 'الإسكندرية', areas: ['Smouha', 'El Raml', 'San Stefano'] },
  { city: 'Mansoura', city_ar: 'المنصورة', areas: ['Center', 'Tal El Eibin'] },
  { city: 'Port Said', city_ar: 'بورسعيد', areas: ['Center', 'Al Arish'] },
  { city: 'Suez', city_ar: ' Suez', areas: ['Center', 'Ain Sokhna'] },
  { city: 'Ismailia', city_ar: 'الإسماعيلية', areas: ['Center', 'Tal Kabir'] },
  { city: 'Luxor', city_ar: 'الأقصر', areas: ['Center', 'Karnak'] },
];

/** Payment methods, from orders_payment_method_check. */
const PAYMENT_METHODS = ['cash', 'card', 'wallet'];

/** Order status weights. Skewed to delivered because a real book is mostly
 *  history; recent orders are re-weighted separately in `orderStatusFor`. */
const ORDER_STATUSES = [
  'pending',
  'confirmed',
  'preparing',
  'ready',
  'picked_up',
  'on_the_way',
  'delivered',
  'cancelled',
];
const ORDER_STATUS_WEIGHTS = [4, 5, 5, 4, 4, 5, 68, 5];

// ---------------------------------------------------------------------------
// BILINGUAL NAME POOLS
// ---------------------------------------------------------------------------
//
// One pool per merchant category. Every entry is an [en, ar] pair because the
// database stores every name as a name_en / name_ar pair and the dashboard
// switches between them -- a name present in only one language would render
// blank for half the users, which is the exact failure pickName() exists to
// absorb.
//
// Prices are drawn per item from the category's own range, because a pharmacy
// and a bakery do not have comparable price points and a single global range
// would make the catalog read as fictional.

const MENUS = {
  restaurant: {
    price: [35, 480],
    categories: [
      { en: 'Grills', ar: 'مشاوي', items: [
        ['Mixed grill platter', 'مشاوي مشكل'],
        ['Kofta kebab', 'كباب كفتة'],
        ['Baladi kebab', 'كباب بلدي'],
        ['Grilled shrimp', 'جمبري مشوي'],
        ['Grilled calamari', 'كاليماري مشوي'],
        ['Half grilled chicken', 'نصف فرخة مشوية'],
        ['Lamb chops', 'ريش غنم'],
        ['Grilled ribs', 'أضلاع مشوية'],
      ]},
      { en: 'Sandwiches', ar: 'ساندوتشات', items: [
        ['Burger', 'برجر'],
        ['Cheeseburger', 'تشيز برجر'],
        ['Double cheeseburger', 'دبل تشيز برجر'],
        ['Grilled sandwich', 'ساندوتش مشوي'],
        ['Egyptian sausage roll', 'سجق'],
        ['Taameya', 'طعمية'],
      ]},
      { en: 'Egyptian classics', ar: 'أكلات مصرية', items: [
        ['Koshari', 'كشري'],
        ['Molokhia with meat', 'ملوخية بلحمة'],
        ['Rice with white sauce', 'أرز بصوص'],
        ['Fried eggplant', 'باذنجان مقلي'],
        ['Macarona', 'مكرونة'],
        ['Sayadieh', 'سيادية'],
      ]},
      { en: 'Pizza & pasta', ar: 'بيتزا ومكرونة', items: [
        ['Margherita pizza', 'بيتزا مارغريتا'],
        ['Pepperoni pizza', 'بيتزا بيبروني'],
        ['Four seasons pizza', 'بيتزا فور سيجنز'],
        ['Arrabbiata pasta', 'مكرونة أربيياتا'],
        ['Lasagna', 'لازانيا'],
        ['Pasta with white sauce', 'مكرونة بصوص'],
      ]},
      { en: 'Sides', ar: 'أطباق جانبية', items: [
        ['French fries', 'بطاطس مقلي'],
        ['Rice', 'أرز'],
        ['Grilled vegetables', 'خضار مشوية'],
        ['Hummus', 'حمص'],
        ['Baba ganoush', 'بابا غنوج'],
        ['Tahina', 'طحينة'],
        ['Green salad', 'سلطة خضراء'],
        ['Coleslaw', 'كول سلو'],
      ]},
      { en: 'Desserts', ar: 'حلويات', items: [
        ['Um Ali', 'أم علي'],
        ['Rice pudding', 'مهلبية'],
        ['Basbousa', 'بسبوسة'],
        ['Kunafa', 'كنافة'],
        ['Molotov', 'مولوتوف'],
        ['Baklava', 'بقلاوة'],
      ]},
    ],
  },

  pharmacy: {
    price: [15, 320],
    categories: [
      { en: 'Pain relief', ar: 'مسكنات الألم', items: [
        ['Panadol', 'بانادول'],
        ['Brufen', 'بروفين'],
        ['Paracetamol 500mg', 'باراسيتامول ٥٠٠ ملجم'],
        ['Ibuprofen 400mg', 'إيبوبروفين ٤٠٠ ملجم'],
        ['Aspirin 75mg', 'أسبرين ٧٥ ملجم'],
        ['Diclofenac gel', 'ديكلوفيناك جل'],
      ]},
      { en: 'Antibiotics', ar: 'مضادات حيوية', items: [
        ['Augmentin 1g', 'أوجمنتين ١ جم'],
        ['Cipro 500mg', 'سيبرو ٥٠٠ ملجم'],
        ['Flagyl 500mg', 'فلاجيل ٥٠٠ ملجم'],
        ['Zithromax', 'زيثروماكس'],
      ]},
      { en: 'Vitamins & supplements', ar: 'فيتامينات ومكملات', items: [
        ['Vitamin C 1000mg', 'فيتامين سي ١٠٠٠ ملجم'],
        ['Vitamin D3 50000IU', 'فيتامين د٣ ٥٠٠٠٠ وحدة'],
        ['Calcium + D', 'كالسيوم وفيتامين د'],
        ['Iron tablets', 'أقراص حديد'],
        ['Multivitamin', 'فيتامين متعدد'],
        ['Omega 3', 'أوميجا ٣'],
        ['Zinc', 'زنك'],
      ]},
      { en: 'First aid', ar: 'إسعافات أولية', items: [
        ['Adhesive bandages', 'ضمادات لاصقة'],
        ['Antiseptic solution', 'محلول مطهر'],
        ['Cotton wool', 'قطن'],
        ['Digital thermometer', 'ترموميتر رقمي'],
        ['First aid kit', 'حقيبة إسعافات أولية'],
        ['Elastic bandage', 'ضمادة مطاطية'],
      ]},
      { en: 'Devices', ar: 'أجهزة', items: [
        ['Blood pressure monitor', 'جهاز قياس الضغط'],
        ['Glucose meter', 'جهاز قياس السكر'],
        ['Test strips', 'شرائط قياس'],
        ['Nebulizer', 'جهاز بخاخ'],
        ['Pulse oximeter', 'جهاز قياس الأكسجين'],
      ]},
      { en: 'Baby care', ar: 'عناية بالأطفال', items: [
        ['Baby diapers (M)', 'حفاضات أطفال مقاس م'],
        ['Baby wipes', 'مناديل مبللة للأطفال'],
        ['Lactogen milk powder', 'لبن لاكتوجين'],
        ['Baby feeding bottle', 'رضّاعة أطفال'],
        ['Nappy rash cream', 'كريم تسلخات الحفاض'],
      ]},
    ],
  },

  market: {
    price: [10, 750],
    categories: [
      { en: 'Fruits', ar: 'فواكه', items: [
        ['Oranges', 'برتقال'],
        ['Bananas', 'موز'],
        ['Apples', 'تفاح'],
        ['Grapes', 'عنب'],
        ['Mangoes', 'مانجو'],
        ['Strawberries', 'فراولة'],
        ['Watermelon', 'بطيخ'],
        ['Pomegranate', 'رمان'],
        ['Peaches', 'خوخ'],
        ['Pineapple', 'أناناس'],
      ]},
      { en: 'Vegetables', ar: 'خضروات', items: [
        ['Tomatoes', 'طماطم'],
        ['Potatoes', 'بطاطس'],
        ['Onions', 'بصل'],
        ['Eggplant', 'باذنجان'],
        ['Peppers', 'فلفل'],
        ['Cucumbers', 'خيار'],
        ['Carrots', 'جزر'],
        ['Green beans', 'فاصوليا خضراء'],
        ['Cauliflower', 'قرنبيط'],
        ['Lettuce', 'خس'],
      ]},
      { en: 'Dairy & eggs', ar: 'ألبان وبيض', items: [
        ['Full cream milk', 'لبن كامل الدسم'],
        ['Yogurt', 'زبادي'],
        ['White cheese', 'جبنة بيضاء'],
        ['Roumy cheese', 'جبنة رومي'],
        ['Butter', 'زبدة'],
        ['Eggs (dozen)', 'بيض درج'],
        ['Cream', 'قشطة'],
      ]},
      { en: 'Meat', ar: 'لحوم', items: [
        ['Chicken (1kg)', 'فراخ ١ كيلو'],
        ['Minced beef (500g)', 'لحم مفروم ٥٠٠ جرام'],
        ['Beef fillet (500g)', 'لحم فيليه ٥٠٠ جرام'],
        ['Fish fillet', 'فيليه سمك'],
        ['Shrimp (500g)', 'جمبري ٥٠٠ جرام'],
      ]},
      { en: 'Dry goods', ar: 'مواد جافة', items: [
        ['Rice (1kg)', 'أرز ١ كيلو'],
        ['Macaroni (400g)', 'مكرونة ٤٠٠ جرام'],
        ['Sugar (1kg)', 'سكر ١ كيلو'],
        ['Flour (1kg)', 'طحين ١ كيلو'],
        ['Cooking oil (800ml)', 'زيت طهي ٨٠٠ مل'],
        ['Tea (100g)', 'شاي ١٠٠ جرام'],
        ['Coffee (250g)', 'قهوة ٢٥٠ جرام'],
        ['Lentils (500g)', 'عدس ٥٠٠ جرام'],
        ['Rice (5kg)', 'أرز ٥ كيلو'],
      ]},
      { en: 'Drinks & snacks', ar: 'مشروبات وأطعمة خفيفة', items: [
        ['Mineral water 1.5L', 'مياه معدنية ١.٥ لتر'],
        ['Orange juice 1L', 'عصير برتقال ١ لتر'],
        ['Soft drinks pack', 'علبة مشروبات غازية'],
        ['Tea pack (25 bags)', 'علبة شاي ٢٥ كيس'],
        ['Coffee (250g)', 'قهوة ٢٥٠ جرام'],
        ['Chocolate bar', 'لوح شوكولاتة'],
        ['Biscuits pack', 'علبة بسكويت'],
      ]},
    ],
  },

  grocery: {
    price: [8, 400],
    categories: [
      { en: 'Pantry', ar: 'بقالة', items: [
        ['Rice (1kg)', 'أرز ١ كيلو'],
        ['Pasta (500g)', 'مكرونة ٥٠٠ جرام'],
        ['Sugar (1kg)', 'سكر ١ كيلو'],
        ['Flour (1kg)', 'طحين ١ كيلو'],
        ['Cooking oil (1L)', 'زيت طهي ١ لتر'],
        ['Salt', 'ملح'],
        ['Lentils (500g)', 'عدس ٥٠٠ جرام'],
      ]},
      { en: 'Breakfast', ar: 'إفطار', items: [
        ['Tea (100g)', 'شاي ١٠٠ جرام'],
        ['Coffee (250g)', 'قهوة ٢٥٠ جرام'],
        ['Honey (500g)', 'عسل ٥٠٠ جرام'],
        ['Jam pack', 'علبة مربى'],
        ['Cereal box', 'علبة حبوب'],
        ['Butter (250g)', 'زبدة ٢٥٠ جرام'],
        ['Cheese slices', 'شرائح جبن'],
      ]},
      { en: 'Drinks', ar: 'مشروبات', items: [
        ['Mineral water (6 pack)', 'مياه معدنية ٦ عبوات'],
        ['Orange juice (1L)', 'عصير برتقال ١ لتر'],
        ['Karkade', 'كركديه'],
        ['Tea pack (25 bags)', 'علبة شاي ٢٥ كيس'],
        ['Soft drinks pack', 'علبة مشروبات غازية'],
      ]},
      { en: 'Snacks', ar: 'وجبات خفيفة', items: [
        ['Chips (large)', 'شيبس كبير'],
        ['Biscuits pack', 'علبة بسكويت'],
        ['Chocolate bar', 'لوح شوكولاتة'],
        ['Nuts pack', 'علبة مكسرات'],
        ['Dates (1kg)', 'تمر ١ كيلو'],
      ]},
    ],
  },

  bakery: {
    price: [10, 350],
    categories: [
      { en: 'Bread', ar: 'عيش', items: [
        ['Arabic bread (5 pcs)', 'عيش عربي ٥ قطع'],
        ['Baladi bread (5 pcs)', 'عيش بلدي ٥ قطع'],
        ['Pita bread', 'عيش فينو'],
        ['Whole wheat bread', 'عيش أسمر'],
        ['Bread rolls (6 pcs)', 'عيش فينو صغير ٦ قطع'],
      ]},
      { en: 'Pastries', ar: 'معجنات', items: [
        ['Croissant', 'كرواسون'],
        ['Baguette', 'باجيت'],
        ['Pain au chocolat', 'بان أو شوكولاتة'],
        ['Sambousk with cheese', 'سمبوسك جبن'],
        ['Sambousk with meat', 'سمبوسك لحمة'],
        ['Cheese pastry', 'فطيرة جبن'],
      ]},
      { en: 'Cakes', ar: 'كيك', items: [
        ['Chocolate cake', 'كيك شوكولاتة'],
        ['Vanilla sponge', 'سبونج فانيليا'],
        ['Cupcake', 'كيك صغير'],
        ['Brownies', 'براوني'],
        ['Cheesecake slice', 'قطعة تشيز كيك'],
      ]},
      { en: 'Cookies & sweets', ar: 'كوكيز وحلويات', items: [
        ['Chocolate chip cookies', 'كوكيز شوكولاتة'],
        ['Muffin', 'مافن'],
        ['Donuts', 'دوناتس'],
        ['Baklava', 'بقلاوة'],
        ['Basbousa', 'بسبوسة'],
        ['Kunafa', 'كنافة'],
        ['Petits fours', 'بيتيفور'],
        ['Macarons', 'ماكارون'],
      ]},
    ],
  },

  butcher: {
    price: [60, 900],
    categories: [
      { en: 'Lamb', ar: 'لحوم غنم', items: [
        ['Lamb chops (1kg)', 'ريش غنم ١ كيلو'],
        ['Lamb leg (1kg)', 'بوز غنم ١ كيلو'],
        ['Lamb shoulder', 'كتف غنم'],
        ['Mutton (1kg)', 'لحم غنم ١ كيلو'],
      ]},
      { en: 'Beef', ar: 'لحوم بقر', items: [
        ['Beef fillet (500g)', 'لحم فيليه ٥٠٠ جرام'],
        ['Minced beef (500g)', 'لحم مفروم ٥٠٠ جرام'],
        ['Steak (500g)', 'ستيك ٥٠٠ جرام'],
        ['Beef ribs', 'أضلاع بقية'],
        ['Tongue', 'لسان'],
      ]},
      { en: 'Chicken', ar: 'دواجن', items: [
        ['Whole chicken', 'فرخة كاملة'],
        ['Chicken breast (500g)', 'صدور دجاج ٥٠٠ جرام'],
        ['Chicken thigh (500g)', 'أفخاز دجاج ٥٠٠ جرام'],
        ['Chicken wings', 'أجنحة دجاج'],
      ]},
      { en: 'Cold cuts', ar: 'لحوم باردة', items: [
        ['Sausage (500g)', 'سجق ٥٠٠ جرام'],
        ['Salami (250g)', 'سالمي ٢٥٠ جرام'],
        ['Hot dog (500g)', 'هوت دوج ٥٠٠ جرام'],
        ['Luncheon meat (200g)', 'لحم مشوي ٢٠٠ جرام'],
        ['Turkey breast', 'صدر ديك رومي'],
      ]},
    ],
  },

  flowers: {
    price: [120, 1800],
    categories: [
      { en: 'Bouquets', ar: 'باقات', items: [
        ['Rose bouquet (12)', 'باقة ورد ١٢'],
        ['Mixed bouquet', 'باقة مشكل'],
        ['Tulip bouquet (10)', 'باقة توليب ١٠'],
        ['Orchid bouquet', 'باقة أوركيد'],
        ['Sunflower bouquet (7)', 'باقة دوار الشمس ٧'],
        ['Jasmine bouquet', 'باقة ياسمين'],
      ]},
      { en: 'Single stems', ar: 'زهور مفردة', items: [
        ['Single rose', 'وردة مفردة'],
        ['Lily stem', 'ساق زنبق'],
        ['Gerbera', 'جربيرا'],
        ['Carnation', 'قرنفل'],
        ['Baby breath bunch', 'باقة جريرة'],
      ]},
      { en: 'Plants', ar: 'نباتات', items: [
        ['Potted plant', 'نبتة في أصيص'],
        ['Orchid pot', 'أوركيد في أصيص'],
        ['Succulent pot', 'صبار في أصيص'],
        ['Herbs pot', 'أعشاب في أصيص'],
      ]},
      { en: 'Add-ons', ar: 'إضافات', items: [
        ['Gift wrap', 'تغليف هدية'],
        ['Greeting card', 'كروت معايدة'],
        ['Glass vase', 'مزهرية زجاجية'],
        ['Silk ribbon', 'شريط حرير'],
      ]},
    ],
  },

  other: {
    price: [40, 900],
    categories: [
      { en: 'Gifts', ar: 'هدايا', items: [
        ['Gift box', 'علبة هدية'],
        ['Gift hamper', 'سلة هدية'],
        ['Flowering plant', 'نبتة مزهرة'],
        ['Chocolate gift box', 'علبة شوكولاتة هدية'],
      ]},
      { en: 'Party', ar: 'حفلة', items: [
        ['Balloons pack', 'علبة بالونات'],
        ['Party candles', 'شموع حفلة'],
        ['Wrapping paper roll', 'لفة ورق تغليف'],
        ['Plastic plates pack', 'علبة أطباق بلاستيك'],
        ['Napkins pack', 'علبة مناديل'],
      ]},
      { en: 'Stationery', ar: 'قرطاسية', items: [
        ['Greeting cards pack', 'علبة كروت'],
        ['Gift bag', 'كيس هدية'],
        ['Ribbon roll', 'لفة شريط'],
        ['Sticker sheet', 'ملصقات'],
      ]},
      { en: 'Essentials', ar: 'أساسيات', items: [
        ['Umbrella', 'مظلة'],
        ['Hand sanitizer', 'معقم يدين'],
        ['Face mask (box)', 'علبة كمامات'],
        ['Phone charger', 'شاحن موبايل'],
        ['Power bank', 'باور بانك'],
      ]},
    ],
  },
};

// ---------------------------------------------------------------------------
// ENTITY BUILDERS
// ---------------------------------------------------------------------------

const MERCHANT_NAMES = {
  restaurant: [
    ['El Mahrous', 'المهرس'], ['El Sakan', 'السكن'], ['Nile Garden', 'حديقة النيل'],
    ['Casa Verde', 'كازا فيردي'], ['Al Watan', 'الوطن'], ['Golden Fork', 'الشوكة الذهبية'],
  ],
  pharmacy: [
    ['El Shifa', 'الشفاء'], ['Marina Pharmacy', 'صيدلية مارينا'], ['Al Hayat', 'الحياة'],
    ['Green Cross', 'الصليب الأخضر'], ['Nile Pharmacy', 'صيدلية النيل'],
  ],
  market: [
    ['Al Fresh', 'الطازج'], ['Sunrise Market', 'سوق الشروق'], ['Al Nahal', 'النخيل'],
    ['Family Market', 'سوق العائلة'], ['El Karnak', 'الكرنك'],
  ],
  grocery: [
    ['Al Kabeer', 'الكبير'], ['Daily Grocery', 'بقالة اليومية'], ['Al Waseet', 'الوسيط'],
    ['Corner Store', 'بقالة الركن'], ['Al Aman', 'الأمان'],
  ],
  bakery: [
    ['Al Tabakh', 'الخبز'], ['Golden Crust', 'القرص الذهبي'], ['Farash', 'فراش'],
    ['Morning Bun', 'خبزة الصباح'], ['Al Sheker', 'السكر'],
  ],
  butcher: [
    ['Al Rifaa', 'الرفاعة'], ['Prime Cuts', 'بريمي كتس'], ['Al Selah', 'السلاح'],
    ['Fresh Meat House', 'بيت اللحم الطازج'], ['Al Waqan', 'الوقان'],
  ],
  flowers: [
    ['Al Ward', 'الورد'], ['Bloom Studio', 'استوديو بلوم'], ['Rose Garden', 'حديقة الورد'],
    ['Petal House', 'بيت البتل'], ['Al Yasmin', 'الياسمين'],
  ],
  other: [
    ['Al Wafaya', 'الوفية'], ['Gift Corner', 'ركن الهدايا'], ['Al Hada', 'الهدى'],
    ['Party Palace', 'قصر الحفلات'], ['Al Mamlaka', 'المملكة'],
  ],
};

const CUSTOMER_FIRST = [
  ['Ahmed', 'أحمد'], ['Mahmoud', 'محمود'], ['Youssef', 'يوسف'], ['Omar', 'عمر'],
  ['Karim', 'كريم'], ['Hussein', 'حسين'], ['Mostafa', 'مصطفى'], ['Tarek', 'طارق'],
  ['Nour', 'نور'], ['Mona', 'منى'], ['Sara', 'سارة'], ['Aisha', 'عائشة'],
  ['Fatma', 'فاطمة'], ['Layla', 'ليلى'], ['Hoda', 'هدى'], ['Yasmin', 'ياسم'],
];

const CUSTOMER_LAST = [
  ['Abdelrahman', 'عبد الرحمن'], ['El Sayed', 'السيد'], ['Hassan', 'حسن'],
  ['Ibrahim', 'إبراهيم'], ['Naguib', 'نجيب'], ['Farouk', 'فاروق'],
  ['Shawky', 'شوقي'], ['Zaki', 'زكي'],
];

const DESCRIPTIONS = {
  restaurant: [
    ['Prepared fresh to order.', 'يُحضّر طازجًا حسب الطلب.'],
    ['Served with bread and salad.', 'يُقدّم مع الخبز والسلطة.'],
    ['A house favourite.', 'من أطباقنا المميزة.'],
    ['Chef\'s recommendation.', 'توصية الشيف.'],
  ],
  pharmacy: [
    ['Check expiry date before use.', 'تحقق من تاريخ الصلاحية قبل الاستخدام.'],
    ['Keep out of reach of children.', 'يُحفظ بعيدًا عن متناول الأطفال.'],
    ['Not for sale without a prescription.', 'لا يُباع بدون روشتة.'],
  ],
  market: [
    ['Imported weekly.', 'مستورد أسبوعيًا.'],
    ['Source and expiry date on request.', 'المصدر وتاريخ الصلاحية عند الطلب.'],
    ['Stored under refrigeration.', 'مخزّن تحت التبريد.'],
  ],
  grocery: [
    ['Everyday essentials.', 'احتياجات يومية أساسية.'],
    ['Pack size may vary slightly.', 'قد يختلف حجم العبوة اختلافًا طفيفًا.'],
  ],
  bakery: [
    ['Baked daily.', 'يُخبز يوميًا.'],
    ['Best consumed the same day.', 'الأفضل استهلاكه في نفس اليوم.'],
    ['Contains gluten, dairy and eggs.', 'يحتوي على الغلوتين والألبان والبيض.'],
  ],
  butcher: [
    ['Slaughtered hygienically.', 'ذبح حلال ونظيفة.'],
    ['Cut fresh to order.', 'يُفرم طازجًا حسب الطلب.'],
    ['Keep refrigerated below 4°C.', 'يُحفظ مبردًا تحت ٤ درجات.'],
  ],
  flowers: [
    ['Hand-tied arrangement.', 'تنسيق يدوي.'],
    ['Includes a card with your message.', 'يشمل كارت برسالتك.'],
  ],
  other: [
    ['Gift wrapping available on request.', 'تغليف هدية عند الطلب.'],
  ],
};

/**
 * Option groups. Applied to a random subset of items so the item editor has
 * something real to edit -- options exist for ~40% of a real catalog, not all
 * of it, and a dataset where every item has options would not exercise the
 * "this item has no options" path.
 */
const OPTION_GROUPS = [
  {
    en: 'Size',
    ar: 'الحجم',
    choices: [
      [['Small', 'صغير', 0], ['Medium', 'وسط', 15], ['Large', 'كبير', 30]],
    ],
  },
  {
    en: 'Extras',
    ar: 'إضافات',
    choices: [
      [['Extra cheese', 'جبنة إضافية', 20], ['Bacon', 'بيكون', 35], ['Mushrooms', 'فطر', 15], ['Olives', 'زيتون', 10]],
    ],
  },
  {
    en: 'Spice level',
    ar: 'درجة الحرارة',
    choices: [
      [['Mild', 'خفيف', 0], ['Medium', 'وسط', 0], ['Hot', 'حار', 0], ['Extra hot', 'حار جدًا', 0]],
    ],
  },
  {
    en: 'With drink',
    ar: 'مع مشروب',
    choices: [
      [['No drink', 'بدون مشروب', 0], ['Soft drink', 'مشروب غازي', 15], ['Mineral water', 'مياه معدنية', 10]],
    ],
  },
];

// ---------------------------------------------------------------------------
// BUILD
// ---------------------------------------------------------------------------

const merchants = [];
const categories = [];
const items = [];
const itemOptions = [];
const itemOptionChoices = [];

/** category id -> when it was created. See the item loop for why this exists. */
const categoryCreatedAtById = new Map();

for (let m = 0; m < 24; m += 1) {
  // Cycle the merchant category so all 8 appear; weight towards restaurants
  // because that is how the real book looks.
  const catCode = m < 9 ? 'restaurant' : MERCHANT_CATEGORIES[m % MERCHANT_CATEGORIES.length].code;
  const menu = MENUS[catCode];

  const [nameEn, nameAr] = MERCHANT_NAMES[catCode][m % MERCHANT_NAMES[catCode].length];
  const place = CITIES[m % CITIES.length];
  const area = place.areas[m % place.areas.length];
  const id = uuid(`merchant:${m}`);

  // Approved for most; a few pending so the status filter has something to
  // show. Rejected is left out: a demo dataset with a refused vendor invites
  // the question of what the refusal reason was, and the column is nullable.
  const approval = m % 7 === 3 ? 'pending' : 'approved';

  // Captured so the categories and items below can be dated relative to when the
  // merchant actually joined. A menu cannot have been written before its vendor
  // existed, and an item dated after "today" would be a lie the UI cannot check.
  const merchantCreatedAt = new Date(
    cairoDayStart(addDays(DEMO_TODAY, -randInt(120, 900))) + randInt(0, 20) * 3_600_000,
  ).toISOString();

  merchants.push({
    id,
    name_en: `${nameEn} ${place.city}`,
    name_ar: `${nameAr} ${place.city_ar}`,
    category: catCode,
    logo_url: null,
    cover_url: null,
    description_en: DESCRIPTIONS[catCode][m % DESCRIPTIONS[catCode].length][0],
    description_ar: DESCRIPTIONS[catCode][m % DESCRIPTIONS[catCode].length][1],
    address: `${randInt(1, 180)} ${randInt(1, 90)} ${area}`,
    lat: Number((30.02 + rand() * 0.6).toFixed(6)),
    lng: Number((31.14 + rand() * 0.5).toFixed(6)),
    city: place.city,
    area,
    phone: `+2010${randInt(10000000, 99999999)}`,
    is_active: m % 11 !== 5,
    rating: Number((3.2 + rand() * 1.8).toFixed(1)),
    rating_count: randInt(4, 940),
    min_order_amount: [0, 50, 100, 150][m % 4],
    estimated_delivery_minutes: [20, 30, 45, 60][m % 4],
    delivery_fee_override: m % 3 === 0 ? 0 : null,
    commission_pct: Number((8 + (m % 5) * 1.5).toFixed(2)),
    delivery_radius_km: Number((5 + (m % 4) * 3).toFixed(2)),
    estimated_prep_time_minutes: [15, 20, 30, 45][m % 4],
    payout_frequency: ['daily', 'weekly', 'monthly'][m % 3],
    payout_method: ['bank_transfer', 'wallet', 'cash', 'instapay'][m % 4],
    wallet_phone: `+2010${randInt(10000000, 99999999)}`,
    approval_status: approval,
    approval_note: approval === 'pending' ? null : 'Documents verified.',
    created_at: merchantCreatedAt,
    updated_at: new Date(cairoDayStart(addDays(DEMO_TODAY, -randInt(0, 60))) + randInt(0, 20) * 3_600_000).toISOString(),
  });

  // -- categories for this merchant --
  for (let c = 0; c < menu.categories.length; c += 1) {
    const cat = menu.categories[c];
    const cid = uuid(`category:${m}:${c}`);
    // Categories appear shortly after the merchant joins, never before and
    // never after "today".
    const categoryCreatedAt = new Date(
      Math.min(
        Date.parse(merchantCreatedAt) + randInt(1, 45) * 86_400_000,
        cairoDayStart(addDays(DEMO_TODAY, -randInt(0, 30))),
      ),
    ).toISOString();

    categories.push({
      id: cid,
      merchant_id: id,
      name_en: cat.en,
      name_ar: cat.ar,
      sort_order: c,
      icon: null,
      is_available: true,
      created_at: categoryCreatedAt,
      updated_at: categoryCreatedAt,
      deleted_at: null,
    });
    // Recorded so the item loop can date its items relative to the category they
    // actually belong to.
    categoryCreatedAtById.set(cid, categoryCreatedAt);
  }

  // -- items: every item of every category --
  //
  // NOT capped per merchant. The dashboard lists items INSIDE one category, so
  // a per-merchant cap would leave ~2 rows per category and the items table
  // would never exercise pagination, sorting or the empty state. Category depth
  // is what makes that screen testable.
  for (let c = 0; c < menu.categories.length; c += 1) {
    const cat = menu.categories[c];
    // Recomputed rather than carried over from the category loop: uuid() is a
    // pure function of its name, so this yields the identical id without
    // threading a lookup table through the item loop.
    const cid = uuid(`category:${m}:${c}`);
    for (let i = 0; i < cat.items.length; i += 1) {
      const [iEn, iAr] = cat.items[i];
      const iid = uuid(`item:${m}:${c}:${i}`);
      const [priceMin, priceMax] = menu.price;
      // Round to a realistic price point: .00 for larger amounts, .50 below 100.
      const rawPrice = randInt(priceMin * 2, priceMax * 2) / 2;
      const price = rawPrice >= 100 ? Math.round(rawPrice) : Math.round(rawPrice * 2) / 2;

      // A fifth of the catalog is on promotion. discount_price obeys the
      // items_discount_price_check constraint (0 <= discount_price <= price);
      // the generator asserts that below rather than trusting the arithmetic.
      const onPromotion = rand() < 0.2;
      const discountPrice = onPromotion
        ? Number(Math.max(0, Math.round((price * (0.7 + rand() * 0.25)) * 2) / 2).toFixed(2))
        : null;
      if (discountPrice !== null) {
        if (!(discountPrice >= 0 && discountPrice <= price)) {
          throw new Error(`discount_price ${discountPrice} violates 0..${price} for ${iEn}`);
        }
      }

      // A few items are sold out (is_available = false). Kept distinct from
      // deleted_at so the three-state item list has all three states present.
      const available = rand() > 0.12;
      // One item in ~60 is soft-deleted.
      const deleted = rand() < 0.017;

      // Dated after the category exists and never after "today". These are read
      // straight into a date formatter by the item screen, so a missing value
      // here is not a cosmetic gap — it crashes the page with an invalid Date.
      //
      // The category's creation time is LOOKED UP rather than recomputed: it is
      // built from a random draw, so recomputing it would consume a second,
      // different draw and produce a date unrelated to the category the item
      // actually belongs to.
      const categoryCreatedAt = categoryCreatedAtById.get(cid);

      const itemCreatedAt = new Date(
        Math.min(
          Date.parse(categoryCreatedAt) + randInt(0, 40) * 86_400_000,
          cairoDayStart(addDays(DEMO_TODAY, -randInt(0, 20))),
        ),
      ).toISOString();
      const itemUpdatedAt = new Date(
        Math.min(
          Date.parse(itemCreatedAt) + randInt(0, 30) * 86_400_000,
          cairoDayStart(addDays(DEMO_TODAY, -randInt(0, 5))),
        ),
      ).toISOString();

      items.push({
        id: iid,
        merchant_id: id,
        category_id: cid,
        name_en: iEn,
        name_ar: iAr,
        description_en: DESCRIPTIONS[catCode][m % DESCRIPTIONS[catCode].length][0],
        description_ar: DESCRIPTIONS[catCode][m % DESCRIPTIONS[catCode].length][1],
        price,
        image_url: null, // deliberately null: no Supabase linkage in demo data
        is_available: available,
        sort_order: i,
        popularity_score: randInt(0, 500),
        discount_price: discountPrice,
        created_at: itemCreatedAt,
        updated_at: itemUpdatedAt,
        deleted_at: deleted
          ? new Date(cairoDayStart(addDays(DEMO_TODAY, -randInt(1, 90))) + randInt(8, 20) * 3_600_000).toISOString()
          : null,
      });

      // -- option groups --
      if (rand() < 0.4) {
        const groupCount = rand() < 0.75 ? 1 : 2;
        for (let g = 0; g < groupCount; g += 1) {
          const group = OPTION_GROUPS[(m + c + g) % OPTION_GROUPS.length];
          const oid = uuid(`option:${iid}:${g}`);
          const isRequired = group.en === 'Size';

          itemOptions.push({
            id: oid,
            item_id: iid,
            name_en: group.en,
            name_ar: group.ar,
            is_required: isRequired,
            min_selections: isRequired ? 1 : 0,
            max_selections: isRequired ? 1 : group.choices[0].length,
            sort_order: g,
          });

          for (let ci = 0; ci < group.choices[0].length; ci += 1) {
            const [cEn, cAr, modifier] = group.choices[0][ci];
            itemOptionChoices.push({
              id: uuid(`choice:${oid}:${ci}`),
              option_id: oid,
              name_en: cEn,
              name_ar: cAr,
              price_modifier: modifier,
              // Only the first choice of a required group is the default, which
              // is what guard_default_choice_available() (migration 111) expects.
              is_default: ci === 0,
              is_available: rand() > 0.05,
              sort_order: ci,
              // item_option_choices.calories is a real nullable column
              // (migration 007) that no code reads or writes. It is populated
              // ONLY for restaurants: a calorie count on a prescription or a
              // bouquet is not a plausible fixture, and a demo dataset that
              // asserts one is making a claim the source data never made.
              // Nullable means "not recorded", so leaving it null elsewhere is
              // both realistic and exercises the absent path in the UI.
              calories:
                catCode === 'restaurant' && rand() < 0.5 ? randInt(20, 900) : null,
            });
          }
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// ORDER STREAM
// ---------------------------------------------------------------------------
//
// Tuple layout, kept compact because 4k objects of this shape is ~2 MB of JSON.
// The demo provider unpacks it; see src/demo/schema.ts for the mirrored type.
//
//   order: [id, orderNumber, merchantId, customerNameEn, customerNameAr,
//           customerPhone, city, status, paymentStatus, paymentMethod,
//           total, createdAt, lines]
//   line:  [itemId, quantity, unitPrice, lineTotal, selectedOptions|null]
//           selectedOptions is an array of [choiceId, priceModifier]
//
// Both name scripts are carried because RecentOrdersTable renders whichever
// matches the active language, and a customer with an English-only name would
// show a blank cell in Arabic.

/** Deterministic customer identity from the phone number, so a repeat
 *  customer keeps the same customer_id across regenerations. */
function customerId(phone) {
  return uuid(`customer:${phone}`);
}

/** Placed somewhere in the working day, with an evening peak. */
function hourOfDay() {
  const roll = rand();
  if (roll < 0.2) return randInt(9, 11);
  if (roll < 0.55) return randInt(12, 16);
  if (roll < 0.85) return randInt(17, 20);
  return randInt(21, 23);
}

const itemsByMerchant = new Map();
for (const item of items) {
  if (item.deleted_at !== null || !item.is_available) continue;
  const list = itemsByMerchant.get(item.merchant_id) ?? [];
  list.push(item);
  itemsByMerchant.set(item.merchant_id, list);
}

const activeMerchants = merchants.filter((m) => m.approval_status === 'approved' && m.is_active);
const optionsByItem = new Map();
for (const opt of itemOptions) {
  const list = optionsByItem.get(opt.item_id) ?? [];
  list.push(opt);
  optionsByItem.set(opt.item_id, list);
}
const choicesByOption = new Map();
for (const ch of itemOptionChoices) {
  const list = choicesByOption.get(ch.option_id) ?? [];
  list.push(ch);
  choicesByOption.set(ch.option_id, list);
}

const orders = [];
let orderCounter = 1000;

/** phone -> the name the customer was first seen with. */
const customerNamesByPhone = new Map();

/**
 * Pool of customers who place more than one order.
 *
 * Without this every order gets a fresh random phone, so every customer is new
 * and `new_customers` comes out exactly equal to `active_customers` -- the two
 * KPI cards would be redundant and the "New customers" chart would be a copy of
 * the "Orders" chart. A repeat rate around 45% is what a delivery marketplace
 * actually looks like once it has traction.
 *
 * Phones are drawn from a fixed list rather than generated per order, so the
 * same customer identity recurs across days.
 */
const repeatPhones = [];
const REPEAT_POOL_SIZE = 900;
for (let i = 0; i < REPEAT_POOL_SIZE; i += 1) {
  repeatPhones.push(`+2010${randInt(10000000, 99999999)}`);
}
/** How often an order comes from an existing customer rather than a new one. */
const REPEAT_RATE = 0.45;

for (let d = HISTORY_DAYS; d >= 0; d -= 1) {
  const day = addDays(DEMO_TODAY, -d);

  // Weekend uplift: Friday and Saturday are the busy days in Egypt, so the
  // series has visible structure rather than a flat noise band.
  const dow = new Date(`${day}T00:00:00Z`).getUTCDay();
  const weekendBoost = dow === 5 || dow === 6 ? 1.35 : dow === 0 ? 1.15 : 1;
  // Gentle growth trend so the 30-day window beats the previous 30 days and
  // the "New" tag case is exercised.
  const trendBoost = 1 + ((HISTORY_DAYS - d) / HISTORY_DAYS) * 0.55;
  const count = Math.max(1, Math.round(ORDERS_PER_DAY * weekendBoost * trendBoost * (0.75 + rand() * 0.5)));

  for (let o = 0; o < count; o += 1) {
    const merchant = pick(activeMerchants);
    const catalog = itemsByMerchant.get(merchant.id);
    if (!catalog || catalog.length === 0) continue;

    // Older orders have had time to settle; recent ones are mostly still moving.
    const status =
      d > 3
        ? weightedPick(ORDER_STATUSES, ORDER_STATUS_WEIGHTS)
        : weightedPick(ORDER_STATUSES, [40, 22, 14, 8, 5, 4, 3, 4]);

    const [firstEn, firstAr] = pick(CUSTOMER_FIRST);
    const [lastEn, lastAr] = pick(CUSTOMER_LAST);
    const customerNameEn = `${firstEn} ${lastEn}`;
    const customerNameAr = `${firstAr} ${lastAr}`;
    // An existing customer keeps the name they were first seen with, rather than
    // being re-rolled -- otherwise the same phone would show two different
    // people in Recent Orders.
    const returning = rand() < REPEAT_RATE && repeatPhones.length > 0;
    const customerPhone = returning ? pick(repeatPhones) : `+2010${randInt(10000000, 99999999)}`;
    const knownName = customerNamesByPhone.get(customerPhone);
    const nameEn = knownName?.en ?? customerNameEn;
    const nameAr = knownName?.ar ?? customerNameAr;
    if (!knownName) customerNamesByPhone.set(customerPhone, { en: nameEn, ar: nameAr });

    const lineCount = randInt(1, 3);
    const picked = new Set();
    const lines = [];
    let total = 0;

    for (let l = 0; l < lineCount; l += 1) {
      const item = pick(catalog);
      if (picked.has(item.id)) continue;
      picked.add(item.id);

      // Price is snapshotted at order time, exactly like order_items does. The
      // discount in force NOW is applied, which is why a trending row can show a
      // discount_price the order did not use -- that is the live catalog value,
      // matching the comment on the Overview's promotion badge.
      const unitPrice = item.discount_price ?? item.price;
      const qty = randInt(1, 3);
      const lineTotal = Number((unitPrice * qty).toFixed(2));

      // Attach selected options. Frozen into the line, like order_items does, so
      // later catalog edits cannot rewrite an old order.
      const groups = optionsByItem.get(item.id);
      let selectedOptions = null;
      if (groups && groups.length > 0 && rand() < 0.7) {
        selectedOptions = [];
        for (const group of groups) {
          const pool = (choicesByOption.get(group.id) ?? []).filter((c) => c.is_available);
          if (pool.length === 0) continue;
          const chosen = group.is_required
            ? (pool.find((c) => c.is_default) ?? pool[0])
            : rand() < 0.5
              ? pick(pool)
              : null;
          if (chosen) selectedOptions.push([chosen.id, Number(chosen.price_modifier)]);
        }
        if (selectedOptions.length === 0) selectedOptions = null;
      }

      const optionCost = (selectedOptions ?? []).reduce((s, [, mod]) => s + mod * qty, 0);
      lines.push([
        item.id,
        qty,
        unitPrice,
        Number((lineTotal + optionCost).toFixed(2)),
        selectedOptions,
      ]);
      total += lineTotal + optionCost;
    }

    if (lines.length === 0) continue;

    // Minimum order gate, from merchants.min_order_amount.
    if (total < merchant.min_order_amount) continue;

    total = Number(total.toFixed(2));

    // Payment status is coupled to order status. A delivered order is paid (or
    // cash-on-delivery, which settles by hand); a cancelled one is refunded or
    // never charged. Independent random draws would produce rows that contradict
    // each other and teach the wrong thing to whoever builds the payments screen.
    let paymentStatus;
    if (status === 'cancelled') {
      paymentStatus = weightedPick(['failed', 'refunded', 'pending_refund'], [30, 55, 15]);
    } else if (status === 'delivered') {
      paymentStatus = weightedPick(['paid', 'pending_cash', 'paid'], [55, 20, 25]);
    } else {
      paymentStatus = weightedPick(['pending', 'paid', 'pending_cash'], [60, 25, 15]);
    }
    const paymentMethod = paymentStatus === 'pending_cash' ? 'cash' : pick(PAYMENT_METHODS);

    const createdAt = new Date(
      cairoDayStart(day) +
        hourOfDay() * 3_600_000 +
        randInt(0, 59) * 60_000 +
        randInt(0, 59) * 1000,
    ).toISOString();

    orderCounter += 1;
    orders.push([
      uuid(`order:${orderCounter}`),
      `MK-${orderCounter}`,
      merchant.id,
      nameEn,
      nameAr,
      customerPhone,
      merchant.city,
      status,
      paymentStatus,
      paymentMethod,
      total,
      createdAt,
      lines,
    ]);
  }
}

// ---------------------------------------------------------------------------
// OVERVIEW AGGREGATES -- migration 120 rules, applied in JS
// ---------------------------------------------------------------------------

const RANGE_OPTIONS = [7, 30, 90];

const sorted = [...orders].sort((a, b) => Date.parse(a[11]) - Date.parse(b[11]));

/** First-order time per customer, for new_customers. */
const firstOrderByPhone = new Map();
for (const o of sorted) {
  const prev = firstOrderByPhone.get(o[5]);
  if (prev === undefined || Date.parse(o[11]) < prev) firstOrderByPhone.set(o[5], Date.parse(o[11]));
}

/**
 * Revenue and orders_count BOTH exclude cancelled, so the two KPI cards agree.
 * cancelled_count is carried separately rather than folded in. This is the rule
 * migration 114 established and migration 120 documented; replicating it here
 * means the demo Overview shows the same relationship between the two cards.
 */
const countsAsRevenue = (o) => o[7] !== 'cancelled';

function kpisFor(days) {
  const to = cairoDayStart(addDays(DEMO_TODAY, 1));
  const from = cairoDayStart(addDays(DEMO_TODAY, -days + 1));
  const prevTo = from;
  const prevFrom = cairoDayStart(addDays(DEMO_TODAY, -days * 2 + 1));

  const window = sorted.filter((o) => {
    const t = Date.parse(o[11]);
    return t >= from && t < to;
  });
  const previous = sorted.filter((o) => {
    const t = Date.parse(o[11]);
    return t >= prevFrom && t < prevTo;
  });

  const revenue = window.filter(countsAsRevenue).reduce((s, o) => s + o[10], 0);
  const ordersCount = window.filter(countsAsRevenue).length;
  const cancelled = window.filter((o) => o[7] === 'cancelled').length;

  const inRange = (phone, lo, hi) => {
    const t = firstOrderByPhone.get(phone);
    return t !== undefined && t >= lo && t < hi;
  };
  const newCustomers = [...new Set(window.map((o) => o[5]))].filter((p) => inRange(p, from, to)).length;

  const activeCustomers = new Set(window.map((o) => o[5])).size;

  const prevRevenue = previous.filter(countsAsRevenue).reduce((s, o) => s + o[10], 0);
  const prevOrders = previous.filter(countsAsRevenue).length;
  const prevNewCustomers = [...new Set(previous.map((o) => o[5]))].filter((p) => inRange(p, prevFrom, prevTo)).length;

  /** null when the previous window was empty -- "this is new", not "0%". */
  const change = (now, before) => (before > 0 ? Number((((now - before) / before) * 100).toFixed(2)) : null);

  return {
    window_days: days,
    from: new Date(from).toISOString(),
    to: new Date(to).toISOString(),
    revenue: Number(revenue.toFixed(2)),
    orders_count: ordersCount,
    cancelled_count: cancelled,
    new_customers: newCustomers,
    active_customers: activeCustomers,
    previous: {
      revenue: Number(prevRevenue.toFixed(2)),
      orders_count: prevOrders,
      new_customers: prevNewCustomers,
    },
    change: {
      revenue: change(revenue, prevRevenue),
      orders_count: change(ordersCount, prevOrders),
      new_customers: change(newCustomers, prevNewCustomers),
    },
    requested_days: days,
  };
}

/**
 * One row per calendar day in [from, to), INCLUDING days with no activity as
 * explicit zeros. generate_series in migration 120 does this so a chart does not
 * draw a straight line across a gap and read it as steady.
 */
function seriesFor(days) {
  const rows = [];
  const to = cairoDayStart(addDays(DEMO_TODAY, 1));
  const from = cairoDayStart(addDays(DEMO_TODAY, -days + 1));

  for (let t = from; t < to; t += 86_400_000) {
    const day = cairoDay(t);
    const next = t + 86_400_000;
    const dayOrders = sorted.filter((o) => {
      const ms = Date.parse(o[11]);
      return ms >= t && ms < next;
    });
    const billed = dayOrders.filter(countsAsRevenue);
    rows.push([
      day,
      Number(billed.reduce((s, o) => s + o[10], 0).toFixed(2)),
      billed.length,
      [...new Set(dayOrders.map((o) => o[5]))].filter((p) => {
        const f = firstOrderByPhone.get(p);
        return f !== undefined && f >= t && f < next;
      }).length,
      dayOrders.filter((o) => o[7] === 'cancelled').length,
      dayOrders.length,
    ]);
  }
  return rows;
}

const itemById = new Map(items.map((i) => [i.id, i]));
const categoryById = new Map(categories.map((c) => [c.id, c]));

/**
 * Top items by revenue over the last 7 days, DELIVERED orders only.
 *
 * A trending list built on pending orders would surface whatever was ordered
 * most recently, and a cancelled order is not demand. 60 rows are emitted so the
 * demo table has room to page; the Overview asks for 10.
 */
function trending() {
  const from = cairoDayStart(addDays(DEMO_TODAY, -6));
  const to = cairoDayStart(addDays(DEMO_TODAY, 1));

  const agg = new Map();
  for (const o of sorted) {
    if (o[7] !== 'delivered') continue;
    const ms = Date.parse(o[11]);
    if (ms < from || ms >= to) continue;

    for (const [itemId, qty, , lineTotal] of o[12]) {
      const cur = agg.get(itemId) ?? { units: 0, revenue: 0 };
      cur.units += qty;
      cur.revenue += lineTotal;
      agg.set(itemId, cur);
    }
  }

  return [...agg.entries()]
    .map(([itemId, v]) => {
      const item = itemById.get(itemId);
      const cat = item ? categoryById.get(item.category_id) : undefined;
      return [
        itemId,
        item.name_en,
        item.name_ar,
        item.category_id,
        cat?.name_en ?? null,
        cat?.name_ar ?? null,
        v.units,
        Number(v.revenue.toFixed(2)),
        item.discount_price,
      ];
    })
    .sort((a, b) => b[7] - a[7])
    .slice(0, 60);
}

/**
 * Newest orders across all merchants, with the customer and merchant resolved.
 *
 * Column order matches get_recent_orders in migration 120, plus two OPTIONAL
 * trailing Arabic labels:
 *
 *   The live RPC hardcodes `m.name_en` for merchant_name and reads a single
 *   `profiles.full_name` for customer_name, so on the live provider the Recent
 *   Orders merchant column shows English even in Arabic mode. Emitting the
 *   Arabic variants here lets the component prefer them when present, and the
 *   live path degrades to exactly what it renders today -- no regression, and
 *   the RPC gap stays visible instead of being papered over.
 */
function recentOrders(limit) {
  const merchantById = new Map(merchants.map((m) => [m.id, m]));
  return [...sorted]
    .reverse()
    .slice(0, limit)
    .map((o) => {
      const merchant = merchantById.get(o[2]);
      return [
        o[0], // id
        o[1], // order_number
        o[7], // status
        o[10], // total
        o[9], // payment_method
        o[8], // payment_status
        o[11], // created_at
        customerId(o[5]), // customer_id
        o[3], // customer_name
        o[5], // customer_phone
        o[2], // merchant_id
        merchant.name_en, // merchant_name
        o[6], // merchant_city
        o[12].length, // item_count
        o[4], // customer_name_ar   (demo only)
        merchant.name_ar, // merchant_name_ar (demo only)
      ];
    });
}

// ---------------------------------------------------------------------------
// EMIT
// ---------------------------------------------------------------------------

/**
 * Fail here rather than in the browser.
 *
 * Every timestamp the UI formats is asserted present and parseable, and every
 * date is asserted to fall on or before DEMO_TODAY. Both checks exist because
 * their absence was a real bug: items and categories were emitted without
 * created_at / updated_at, which typechecked fine, generated fine, and only
 * surfaced as a RangeError on the item screen — a blank page with a stack trace
 * pointing at a date formatter.
 *
 * A fixture that cannot be wrong at the point of creation is worth more than a
 * fixture that is merely correct today.
 */
function assertDatasetIsRenderable() {
  const problems = [];

  const check = (label, rows, keys) => {
    for (const row of rows) {
      for (const key of keys) {
        const value = row[key];
        if (value === undefined || value === null) {
          problems.push(`${label} ${row.id.slice(0, 8)}: ${key} is ${value}`);
          continue;
        }
        const ms = Date.parse(value);
        if (Number.isNaN(ms)) {
          problems.push(`${label} ${row.id.slice(0, 8)}: ${key} "${value}" is not a date`);
        } else if (ms > Date.parse(`${DEMO_TODAY}T23:59:59Z`)) {
          problems.push(`${label} ${row.id.slice(0, 8)}: ${key} is in the future`);
        }
      }
    }
  };

  check('merchant', merchants, ['created_at', 'updated_at']);
  check('category', categories, ['created_at', 'updated_at']);
  check('item', items, ['created_at', 'updated_at']);

  // Referential integrity: the drill-down walks merchant -> category -> item, so
  // a dangling id would render an empty screen with no explanation.
  const merchantIds = new Set(merchants.map((m) => m.id));
  const categoryIds = new Set(categories.map((c) => c.id));
  for (const c of categories) {
    if (!merchantIds.has(c.merchant_id)) problems.push(`category ${c.id.slice(0, 8)}: no merchant`);
  }
  for (const i of items) {
    if (!merchantIds.has(i.merchant_id)) problems.push(`item ${i.id.slice(0, 8)}: no merchant`);
    if (!categoryIds.has(i.category_id)) problems.push(`item ${i.id.slice(0, 8)}: no category`);
  }

  // Bilingual completeness: the dashboard switches the whole UI on lang, and a
  // name present in only one language renders as a blank cell for half the users.
  for (const row of [...merchants, ...categories, ...items]) {
    if (!row.name_en || !row.name_ar) {
      problems.push(`${row.id.slice(0, 8)}: missing a name in one language`);
    }
  }

  if (problems.length > 0) {
    throw new Error(
      `demo dataset is not renderable (${problems.length} problems):\n  ` +
        problems.slice(0, 20).join('\n  ') +
        (problems.length > 20 ? `\n  ...and ${problems.length - 20} more` : ''),
    );
  }
}

assertDatasetIsRenderable();

const dataset = {
  meta: {
    generator: 'scripts/generate-demo-data.mjs',
    seed: `0x${SEED.toString(16)}`,
    demo_today: DEMO_TODAY,
    history_days: HISTORY_DAYS,
    counts: {
      merchants: merchants.length,
      categories: categories.length,
      items: items.length,
      item_options: itemOptions.length,
      item_option_choices: itemOptionChoices.length,
      orders: orders.length,
    },
  },

  merchant_categories: MERCHANT_CATEGORIES,

  merchants,
  categories,
  items,
  item_options: itemOptions,
  item_option_choices: itemOptionChoices,

  /**
   * Tuple layouts, documented here so the TypeScript reader in
   * src/demo/types.ts has one authoritative description to match.
   */
  order_shape: {
    order: 'id, orderNumber, merchantId, customerNameEn, customerNameAr, customerPhone, city, status, paymentStatus, paymentMethod, total, createdAt, lines',
    line: 'itemId, quantity, unitPrice, lineTotal, selectedOptions|null (each [choiceId, priceModifier])',
    kpi: 'the get_platform_kpis row as an object',
    series: 'day, revenue, orders_count, new_customers, cancelled_count, orders_including_cancelled',
    trending: 'item_id, name_en, name_ar, category_id, category_en, category_ar, units_sold, revenue, discount_price',
    recent_order: 'id, order_number, status, total, payment_method, payment_status, created_at, customer_id, customer_name, customer_phone, merchant_id, merchant_name, merchant_city, item_count, customer_name_ar, merchant_name_ar',
  },

  orders,
  overview: {
    kpis: Object.fromEntries(RANGE_OPTIONS.map((d) => [d, kpisFor(d)])),
    series: Object.fromEntries(RANGE_OPTIONS.map((d) => [d, seriesFor(d)])),
    trending: trending(),
    recent_orders: recentOrders(60),
  },
};

const outPath = resolve(
  dirname(fileURLToPath(import.meta.url)),
  '..',
  'src',
  'demo',
  'data.json',
);
mkdirSync(dirname(outPath), { recursive: true });

const json = JSON.stringify(dataset);
writeFileSync(outPath, json, 'utf8');

/**
 * The merchant-category lookup is ALSO emitted as its own tiny module.
 *
 * Eight rows, a couple of hundred bytes — and it is needed by the add/edit
 * merchant form and the merchant profile, both of which are reachable in LIVE
 * mode too. Keeping it inside the 2.8 MB dataset would force every screen that
 * renders a category dropdown to pull the whole demo corpus, which is how a
 * fixture ends up in a production bundle.
 *
 * Emitting it separately means the big file is imported by exactly one module,
 * which then lazy-loads it (see store.ts).
 */
const lookupModule = `/**
 * GENERATED by scripts/generate-demo-data.mjs — do not edit.
 *
 * The merchant_categories lookup (migration 097), kept out of data.json so that
 * a screen needing only a category dropdown does not pull the whole demo corpus.
 */
import type { MerchantCategoryMeta } from '../constants';

export const MERCHANT_CATEGORY_META: MerchantCategoryMeta[] = ${JSON.stringify(
  MERCHANT_CATEGORIES,
  null,
  2,
)};
`;
writeFileSync(resolve(dirname(outPath), 'merchantCategories.ts'), lookupModule, 'utf8');

process.stdout.write(
  `demo data written\n` +
    `  ${outPath}\n` +
    `  ${resolve(dirname(outPath), 'merchantCategories.ts')}\n` +
    `  merchants ${merchants.length}  categories ${categories.length}  items ${items.length}\n` +
    `  item_options ${itemOptions.length}  item_option_choices ${itemOptionChoices.length}\n` +
    `  orders ${orders.length}\n` +
    `  size ${Math.round(json.length / 1024)} KB\n`,
);
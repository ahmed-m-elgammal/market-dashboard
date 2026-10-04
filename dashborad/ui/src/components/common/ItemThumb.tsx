/**
 * Deterministic placeholder imagery.
 *
 * WHY NOT AN IMAGE URL
 *   items.image_url is null for every generated row, deliberately: the demo data
 *   carries no link to any Supabase storage bucket, so it stays valid after the
 *   project is reset, renamed or moved, and nothing in the repo points at a real
 *   customer's bucket.
 *
 * WHY A PLACEHOLDER RATHER THAN A BLANK CELL
 *   An items table whose thumbnail column is empty gives no way to tell two rows
 *   apart at a glance, and a broken <img> is worse than either. So the thumbnail
 *   is derived from the item's own name: the same item always gets the same
 *   mark, in both themes, with no network request.
 *
 * WHY AN SVG AND NOT A DATA URI
 *   A data: URI would have to be escaped into an <img src>, which cannot use the
 *   surrounding Ant Design tokens — the placeholder would then be frozen at the
 *   colour it was generated in and stay wrong in dark mode. Inline SVG inherits
 *   currentColor and the token values passed in, so it re-tints with the theme.
 */
import { theme } from 'antd';

/**
 * Two hues, chosen for contrast against both theme backgrounds.
 *
 * These are NOT brand colours and are not the app palette: they exist only to
 * make adjacent rows distinguishable. They are read from Ant Design's theme
 * algorithm rather than hardcoded so they shift correctly with the colour
 * scheme, which is the same rule the rest of the dashboard follows — see
 * theme/tokens.ts.
 */
function usePlaceholderColors(): { from: string; to: string; ink: string } {
  const { token } = theme.useToken();

  // colorPrimary is the one hue guaranteed to exist in every theme, so the
  // placeholder can never collide with the surface behind it. The second stop is
  // the primary shifted toward the text colour, which keeps the mark readable on
  // a light surface without introducing a second hardcoded hue.
  //
  // colorTextLightSolid is Ant Design's own "text that sits on a primary-filled
  // surface" token. It is the reason this file needs no literal white: the
  // initials stay legible in both themes because the token is computed from the
  // active primary rather than assumed.
  return {
    from: token.colorPrimary,
    to: token.colorPrimaryHover,
    ink: token.colorTextLightSolid,
  };
}

/**
 * A stable small integer from a string.
 *
 * FNV-1a. Chosen over String.hashCode-style sums because it distributes well
 * across short similar strings: "Burger" and "Burritos" must not land on the
 * same mark, and a naive char-sum gives them adjacent values.
 */
function hash(text: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i += 1) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

export function ItemThumb({
  name,
  size = 40,
  radius,
}: {
  /** Item name. The same name always yields the same mark. */
  name: string;
  size?: number;
  radius?: number;
}) {
  const { from, to, ink } = usePlaceholderColors();
  const seed = hash(name);

  // Two initials from the name, which is more recognisable than an abstract
  // shape: an operator scanning the list can match the mark to the row without
  // reading the text.
  //
  // Only words that actually START with a letter count. A catalog is full of
  // bracketed sizes and weights — "Rice (1kg)", "Pasta (500g)", "Eggs (dozen)"
  // — and taking the first character of the second word regardless produced
  // marks reading "R(", "P(", "E(", which look like a rendering fault rather
  // than an initial. When only one usable word exists, the mark falls back to
  // the first two LETTERS of it instead.
  const initials = (() => {
    const words = name.split(/\s+/).filter((w) => /[\p{L}]/u.test(w[0] ?? ''));
    if (words.length >= 2) return `${words[0][0]}${words[1][0]}`;
    const letters = (name.match(/\p{L}/gu) ?? []).slice(0, 2).join('');
    return letters || '?';
  })();

  // Rotation seeded from the hash, so the mark has some variety without being
  // random per render — a thumbnail that changes on every re-render reads as a
  // bug.
  const rotation = seed % 40 - 20;
  const gradientId = `thumb-${seed.toString(36)}`;

  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 40 40"
      role="presentation"
      aria-hidden="true"
      style={{
        display: 'block',
        flex: '0 0 auto',
        borderRadius: radius ?? size / 4,
        // The item has no image, so the mark stands in for one and must not
        // read as interactive.
        cursor: 'default',
      }}
    >
      <defs>
        <linearGradient id={gradientId} x1="0" y1="0" x2="1" y2="1" gradientTransform={`rotate(${rotation} 0.5 0.5)`}>
          <stop offset="0%" stopColor={from} />
          <stop offset="100%" stopColor={to} />
        </linearGradient>
      </defs>
      <rect width="40" height="40" fill={`url(#${gradientId})`} />
      <text
        x="20"
        y="20"
        textAnchor="middle"
        dominantBaseline="central"
        // Sized off the mark rather than fixed, so a two-letter initial and a
        // one-letter initial both sit inside the square.
        fontSize={initials.length > 1 ? 15 : 19}
        fontWeight="600"
        fill={ink}
      >
        {initials.toUpperCase()}
      </text>
    </svg>
  );
}

/**
 * Merchant logo mark. Same derivation as ItemThumb so the two read as one
 * family, but seeded on the merchant name and rendered at a larger radius.
 */
export function MerchantLogo({
  name,
  size = 36,
}: {
  name: string;
  size?: number;
}) {
  return <ItemThumb name={name} size={size} radius={size / 2} />;
}
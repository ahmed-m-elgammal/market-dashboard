// Luhn checksum — pure function used by validateEgyptianNationalId.
//
// Egyptian national IDs (14 digits) end with a check digit computed via
// Luhn over the first 13 digits. This module is split out from validation.ts
// so it can be unit-tested with Jest (the rest of validation.ts depends on
// Deno globals like Deno.env, which Jest cannot import).
//
// Algorithm: walking the digits right-to-left, double every second digit
// (starting with the second-from-right). If doubling produces > 9, subtract
// 9. The sum of all digits must be a multiple of 10.
//
// The rightmost digit is the check digit and is NOT doubled.

/**
 * Returns true if the input passes the Luhn checksum.
 * Input must be a string of digits only; any non-digit character returns false.
 */
export function luhnIsValid(digits: string): boolean {
  if (!/^\d+$/.test(digits)) return false;
  let sum = 0;
  let double = false;
  for (let i = digits.length - 1; i >= 0; i--) {
    let d = digits.charCodeAt(i) - 48; // '0' is 48
    if (double) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
    double = !double;
  }
  return sum % 10 === 0;
}

/**
 * Compute the Luhn check digit for a given number string (without the check
 * digit). Used for generating valid test fixtures.
 */
export function luhnCheckDigit(digitsWithoutCheck: string): number {
  if (!/^\d+$/.test(digitsWithoutCheck)) {
    throw new Error('luhnCheckDigit: input must be digits only');
  }
  // Append 0 as a placeholder check digit. The placeholder occupies the
  // rightmost position, which is NOT doubled by Luhn. So when we replace
  // 0 with the real digit d, the sum increases by exactly d.
  const withPlaceholder = digitsWithoutCheck + '0';
  let sum = 0;
  let double = false; // rightmost (placeholder) is not doubled
  for (let i = withPlaceholder.length - 1; i >= 0; i--) {
    let d = withPlaceholder.charCodeAt(i) - 48;
    if (double) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
    double = !double;
  }
  return (10 - (sum % 10)) % 10;
}

// Haversine distance calculation between two GPS points
// Returns distance in kilometers

export function haversineDistanceKm(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
): number {
  const R = 6371; // Earth radius in km
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLng / 2) * Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function toRad(deg: number): number {
  return deg * (Math.PI / 180);
}

// Estimate delivery time based on distance (20-45 min range)
export function estimateDeliveryMinutes(distanceKm: number): number {
  // Base: 20 min, +3 min per km, clamped to 20-45
  return Math.min(45, Math.max(20, Math.round(20 + distanceKm * 3)));
}

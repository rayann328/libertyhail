import { prisma } from './db.js';
import { broadcast } from './hub.js';

export const ACTIVE = ['ASSIGNED', 'EN_ROUTE_TO_PICKUP', 'ARRIVED', 'PASSENGER_ONBOARD', 'EN_ROUTE_TO_DESTINATION', 'EMERGENCY'];

export const TRANSITIONS = {
  ASSIGNED: ['EN_ROUTE_TO_PICKUP', 'EMERGENCY'],
  EN_ROUTE_TO_PICKUP: ['ARRIVED', 'EMERGENCY'],
  ARRIVED: ['PASSENGER_ONBOARD', 'EMERGENCY'],
  PASSENGER_ONBOARD: ['EN_ROUTE_TO_DESTINATION', 'EMERGENCY'],
  EN_ROUTE_TO_DESTINATION: ['COMPLETED', 'EMERGENCY'],
  EMERGENCY: ['COMPLETED'],
};

const MESSAGES = {
  ASSIGNED: ['Driver Assigned', 'Your driver has been assigned.'],
  EN_ROUTE_TO_PICKUP: ['Driver Started', 'Your driver is on the way.'],
  ARRIVED: ['Driver Arrived', 'Your driver has arrived.'],
  PASSENGER_ONBOARD: ['Trip Started', 'Your trip has started.'],
  EN_ROUTE_TO_DESTINATION: ['On the way', 'You are on the way to your destination.'],
  COMPLETED: ['Trip Completed', 'Your trip has been completed.'],
  CANCELLED: ['Trip Cancelled', 'Your trip has been cancelled.'],
  EMERGENCY: ['Emergency', 'An emergency has been reported on your trip.'],
};

export const tripInclude = {
  driver: { include: { user: { select: { name: true, phone: true } } } },
  vehicle: true,
};

export function distanceKm(lat1, lon1, lat2, lon2) {
  const R = 6371;
  const rad = (d) => (d * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLon = rad(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

// Simple ETA: straight-line distance at an assumed 30 km/h average.
export function progress(trip, lat, lng) {
  if (lat == null || lng == null || !ACTIVE.includes(trip.status)) {
    return { distance_km: null, eta_minutes: null };
  }
  const toPickup = ['ASSIGNED', 'EN_ROUTE_TO_PICKUP', 'ARRIVED'].includes(trip.status);
  const tLat = toPickup ? trip.pickupLatitude : trip.destinationLatitude;
  const tLng = toPickup ? trip.pickupLongitude : trip.destinationLongitude;
  const km = distanceKm(lat, lng, tLat, tLng);
  const eta = trip.status === 'ARRIVED' ? 0 : Math.max(1, Math.ceil((km / 30) * 60));
  return { distance_km: Math.round(km * 100) / 100, eta_minutes: eta };
}

// Trip-level authorization: who may see/track this trip.
export function canAccess(user, trip) {
  if (user.role === 'admin' || user.role === 'dispatcher') return true;
  if (user.role === 'customer') return trip.userId === user.id;
  if (user.role === 'driver') return trip.driver?.userId === user.id;
  return false;
}

export function notify(userId, tripId, type, title, message) {
  return prisma.notification.create({ data: { userId, tripId, type, title, message } });
}

// Changes trip status, writes history, frees the driver when finished, notifies + broadcasts.
export async function applyStatus(trip, status, byUserId, lat, lng) {
  const data = { status };
  if (status === 'PASSENGER_ONBOARD') data.startedAt = new Date();
  const finished = status === 'COMPLETED' || status === 'CANCELLED';
  if (finished) data.completedAt = new Date();

  await prisma.$transaction(async (tx) => {
    await tx.trip.update({ where: { id: trip.id }, data });
    await tx.tripStatusHistory.create({
      data: { tripId: trip.id, status, changedBy: byUserId, latitude: lat ?? null, longitude: lng ?? null },
    });
    if (finished && trip.driverId) {
      await tx.driver.update({ where: { id: trip.driverId }, data: { status: 'AVAILABLE', currentTripId: null } });
    }
  });

  const [title, message] = MESSAGES[status];
  await notify(trip.userId, trip.id, status, title, message);
  broadcast(trip.id, { event: 'trip.status.updated', trip_id: trip.id, status, timestamp: new Date().toISOString() });
}

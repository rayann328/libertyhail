import { prisma } from '../db.js';
import { ACTIVE, TRANSITIONS, tripInclude, canAccess, distanceKm, notify, applyStatus, progress } from '../lib.js';

const CANCELLABLE = ['ASSIGNED', 'EN_ROUTE_TO_PICKUP', 'ARRIVED'];

export async function tripRoutes(app) {
  // Create a trip and auto-assign the nearest available driver.
  app.post('/api/trips', {
    preHandler: [app.auth, app.role('customer')],
    schema: {
      body: {
        type: 'object',
        required: ['pickup_latitude', 'pickup_longitude', 'destination_latitude', 'destination_longitude'],
        properties: {
          pickup_latitude: { type: 'number', minimum: -90, maximum: 90 },
          pickup_longitude: { type: 'number', minimum: -180, maximum: 180 },
          destination_latitude: { type: 'number', minimum: -90, maximum: 90 },
          destination_longitude: { type: 'number', minimum: -180, maximum: 180 },
          pickup_address: { type: 'string' },
          destination_address: { type: 'string' },
        },
      },
    },
  }, async (req, reply) => {
    const b = req.body;
    const active = await prisma.trip.findFirst({ where: { userId: req.user.id, status: { in: ACTIVE } } });
    if (active) return reply.code(409).send({ error: 'You already have an active trip', trip_id: active.id });

    const drivers = await prisma.driver.findMany({
      where: { status: 'AVAILABLE', vehicle: { isNot: null } },
      include: { vehicle: true },
    });
    if (drivers.length === 0) return reply.code(503).send({ error: 'No driver available right now' });

    const dist = (d) =>
      d.lastLatitude == null ? Infinity : distanceKm(d.lastLatitude, d.lastLongitude, b.pickup_latitude, b.pickup_longitude);
    drivers.sort((a, c) => dist(a) - dist(c));
    const driver = drivers[0];

    const trip = await prisma.$transaction(async (tx) => {
      const t = await tx.trip.create({
        data: {
          userId: req.user.id,
          driverId: driver.id,
          vehicleId: driver.vehicle.id,
          pickupLatitude: b.pickup_latitude,
          pickupLongitude: b.pickup_longitude,
          pickupAddress: b.pickup_address,
          destinationLatitude: b.destination_latitude,
          destinationLongitude: b.destination_longitude,
          destinationAddress: b.destination_address,
          status: 'ASSIGNED',
        },
      });
      await tx.tripStatusHistory.create({ data: { tripId: t.id, status: 'ASSIGNED', changedBy: req.user.id } });
      await tx.driver.update({ where: { id: driver.id }, data: { status: 'BUSY', currentTripId: t.id } });
      return t;
    });

    await notify(req.user.id, trip.id, 'ASSIGNED', 'Driver Assigned', 'Your driver has been assigned.');
    await notify(driver.userId, trip.id, 'NEW_TRIP', 'New Trip', 'You have been assigned a new trip.');

    const full = await prisma.trip.findUnique({ where: { id: trip.id }, include: tripInclude });
    return reply.code(201).send({ trip: full });
  });

  // List my trips (customer: own trips, driver: assigned trips).
  app.get('/api/trips', { preHandler: [app.auth] }, async (req) => {
    let where = {};
    if (req.user.role === 'customer') where = { userId: req.user.id };
    else if (req.user.role === 'driver') where = { driver: { userId: req.user.id } };
    const trips = await prisma.trip.findMany({ where, include: tripInclude, orderBy: { requestedAt: 'desc' }, take: 100 });
    return { trips };
  });

  app.get('/api/trips/:id', { preHandler: [app.auth] }, async (req, reply) => {
    const trip = await prisma.trip.findUnique({ where: { id: Number(req.params.id) }, include: tripInclude });
    if (!trip || !canAccess(req.user, trip)) return reply.code(404).send({ error: 'Trip not found' });
    const prog = progress(trip, trip.driver?.lastLatitude, trip.driver?.lastLongitude);
    return { trip, ...prog };
  });

  // Driver updates trip status.
  app.patch('/api/trips/:id/status', {
    preHandler: [app.auth, app.role('driver')],
    schema: {
      body: {
        type: 'object',
        required: ['status'],
        properties: {
          status: { type: 'string', enum: ['EN_ROUTE_TO_PICKUP', 'ARRIVED', 'PASSENGER_ONBOARD', 'EN_ROUTE_TO_DESTINATION', 'COMPLETED', 'EMERGENCY'] },
          latitude: { type: 'number' },
          longitude: { type: 'number' },
        },
      },
    },
  }, async (req, reply) => {
    const trip = await prisma.trip.findUnique({ where: { id: Number(req.params.id) }, include: tripInclude });
    if (!trip || !canAccess(req.user, trip)) return reply.code(404).send({ error: 'Trip not found' });
    const { status, latitude, longitude } = req.body;
    if (!(TRANSITIONS[trip.status] || []).includes(status)) {
      return reply.code(409).send({ error: `Cannot change status from ${trip.status} to ${status}` });
    }
    await applyStatus(trip, status, req.user.id, latitude, longitude);
    return { ok: true, status };
  });

  app.post('/api/trips/:id/cancel', { preHandler: [app.auth] }, async (req, reply) => {
    const trip = await prisma.trip.findUnique({ where: { id: Number(req.params.id) }, include: tripInclude });
    if (!trip || !canAccess(req.user, trip)) return reply.code(404).send({ error: 'Trip not found' });
    if (!CANCELLABLE.includes(trip.status)) return reply.code(409).send({ error: 'Trip can no longer be cancelled' });
    await applyStatus(trip, 'CANCELLED', req.user.id);
    return { ok: true, status: 'CANCELLED' };
  });

  app.get('/api/notifications', { preHandler: [app.auth] }, async (req) => {
    const notifications = await prisma.notification.findMany({
      where: { userId: req.user.id },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
    return { notifications };
  });

  app.post('/api/notifications/:id/read', { preHandler: [app.auth] }, async (req) => {
    await prisma.notification.updateMany({ where: { id: Number(req.params.id), userId: req.user.id }, data: { isRead: true } });
    return { ok: true };
  });
}

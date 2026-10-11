import { prisma } from '../db.js';
import { broadcast } from '../hub.js';
import { ACTIVE, tripInclude, canAccess, progress } from '../lib.js';

export async function trackingRoutes(app) {
  // Driver sends GPS position (every 2-5 s during a trip).
  app.post('/api/drivers/location', {
    preHandler: [app.auth, app.role('driver')],
    schema: {
      body: {
        type: 'object',
        required: ['latitude', 'longitude'],
        properties: {
          latitude: { type: 'number', minimum: -90, maximum: 90 },
          longitude: { type: 'number', minimum: -180, maximum: 180 },
          accuracy: { type: 'number', minimum: 0 },
          altitude: { type: 'number' },
          speed: { type: 'number', minimum: 0 },
          heading: { type: 'number', minimum: 0, maximum: 360 },
          battery_level: { type: 'integer', minimum: 0, maximum: 100 },
          timestamp: { type: 'string' },
        },
      },
    },
  }, async (req, reply) => {
    const b = req.body;
    const driver = await prisma.driver.findUnique({ where: { userId: req.user.id }, include: { vehicle: true } });
    if (!driver || !driver.vehicle) return reply.code(403).send({ error: 'Driver or vehicle not set up' });

    let recordedAt = b.timestamp ? new Date(b.timestamp) : new Date();
    if (isNaN(recordedAt.getTime())) recordedAt = new Date();

    await prisma.driver.update({
      where: { id: driver.id },
      data: { lastLatitude: b.latitude, lastLongitude: b.longitude, lastLocationAt: recordedAt },
    });

    // Only keep history + broadcast while the driver has an active trip.
    if (driver.currentTripId) {
      const trip = await prisma.trip.findUnique({ where: { id: driver.currentTripId } });
      if (trip && ACTIVE.includes(trip.status)) {
        await prisma.vehicleLocation.create({
          data: {
            vehicleId: driver.vehicle.id,
            driverId: driver.id,
            tripId: trip.id,
            latitude: b.latitude,
            longitude: b.longitude,
            accuracy: b.accuracy,
            altitude: b.altitude,
            speed: b.speed,
            heading: b.heading,
            batteryLevel: b.battery_level,
            recordedAt,
          },
        });
        broadcast(trip.id, {
          event: 'vehicle.location.updated',
          trip_id: trip.id,
          vehicle_id: driver.vehicle.id,
          latitude: b.latitude,
          longitude: b.longitude,
          speed: b.speed ?? null,
          heading: b.heading ?? null,
          status: trip.status,
          timestamp: recordedAt.toISOString(),
          ...progress(trip, b.latitude, b.longitude),
        });
      }
    }
    return { ok: true };
  });

  // Driver goes online/offline (not allowed while on a trip).
  app.patch('/api/drivers/me/status', {
    preHandler: [app.auth, app.role('driver')],
    schema: {
      body: { type: 'object', required: ['status'], properties: { status: { type: 'string', enum: ['AVAILABLE', 'OFFLINE'] } } },
    },
  }, async (req, reply) => {
    const driver = await prisma.driver.findUnique({ where: { userId: req.user.id } });
    if (!driver) return reply.code(404).send({ error: 'Driver profile not found' });
    if (driver.currentTripId) return reply.code(409).send({ error: 'Finish your current trip first' });
    await prisma.driver.update({ where: { id: driver.id }, data: { status: req.body.status } });
    return { ok: true, status: req.body.status };
  });

  // Driver's current active trip (used by the driver app on startup).
  app.get('/api/drivers/me/active-trip', { preHandler: [app.auth, app.role('driver')] }, async (req) => {
    const trip = await prisma.trip.findFirst({
      where: { driver: { userId: req.user.id }, status: { in: ACTIVE } },
      include: tripInclude,
    });
    return { trip };
  });

  // Customer: current active trip.
  app.get('/api/trips/active/me', { preHandler: [app.auth, app.role('customer')] }, async (req) => {
    const trip = await prisma.trip.findFirst({ where: { userId: req.user.id, status: { in: ACTIVE } }, include: tripInclude });
    if (!trip) return { trip: null };
    return { trip, ...progress(trip, trip.driver?.lastLatitude, trip.driver?.lastLongitude) };
  });

  app.get('/api/trips/:id/location', { preHandler: [app.auth] }, async (req, reply) => {
    const trip = await prisma.trip.findUnique({ where: { id: Number(req.params.id) }, include: tripInclude });
    if (!trip || !canAccess(req.user, trip)) return reply.code(404).send({ error: 'Trip not found' });
    const d = trip.driver;
    return {
      trip_id: trip.id,
      status: trip.status,
      latitude: d?.lastLatitude ?? null,
      longitude: d?.lastLongitude ?? null,
      last_update: d?.lastLocationAt ?? null,
      ...progress(trip, d?.lastLatitude, d?.lastLongitude),
    };
  });

  app.get('/api/trips/:id/location/history', { preHandler: [app.auth] }, async (req, reply) => {
    const trip = await prisma.trip.findUnique({ where: { id: Number(req.params.id) }, include: tripInclude });
    if (!trip || !canAccess(req.user, trip)) return reply.code(404).send({ error: 'Trip not found' });
    const limit = Math.min(Number(req.query.limit) || 500, 2000);
    const points = await prisma.vehicleLocation.findMany({
      where: { tripId: trip.id },
      orderBy: { recordedAt: 'asc' },
      take: limit,
      select: { latitude: true, longitude: true, speed: true, heading: true, recordedAt: true },
    });
    return { trip_id: trip.id, points };
  });

  // Register push token for FCM.
  app.post('/api/devices', {
    preHandler: [app.auth],
    schema: {
      body: {
        type: 'object',
        required: ['device_id', 'platform'],
        properties: {
          device_id: { type: 'string' },
          push_token: { type: 'string' },
          platform: { type: 'string', enum: ['android', 'ios'] },
        },
      },
    },
  }, async (req) => {
    const b = req.body;
    await prisma.device.upsert({
      where: { userId_deviceId: { userId: req.user.id, deviceId: b.device_id } },
      update: { pushToken: b.push_token, platform: b.platform, lastSeenAt: new Date() },
      create: { userId: req.user.id, deviceId: b.device_id, pushToken: b.push_token, platform: b.platform },
    });
    return { ok: true };
  });
}

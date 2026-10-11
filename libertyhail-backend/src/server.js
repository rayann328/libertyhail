import Fastify from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import rateLimit from '@fastify/rate-limit';
import websocket from '@fastify/websocket';
import { prisma } from './db.js';
import { join, leave } from './hub.js';
import { tripInclude, canAccess, progress } from './lib.js';
import { authRoutes } from './routes/auth.js';
import { tripRoutes } from './routes/trips.js';
import { trackingRoutes } from './routes/tracking.js';

if (!process.env.JWT_SECRET) {
  console.error('Missing JWT_SECRET in .env');
  process.exit(1);
}

const app = Fastify({ logger: true });

await app.register(cors, { origin: true });
await app.register(rateLimit, { max: 300, timeWindow: '1 minute' });
await app.register(jwt, { secret: process.env.JWT_SECRET });
await app.register(websocket);

app.decorate('auth', async (req, reply) => {
  try {
    await req.jwtVerify();
  } catch {
    return reply.code(401).send({ error: 'Unauthorized' });
  }
});

app.decorate('role', (...roles) => async (req, reply) => {
  if (!roles.includes(req.user.role)) return reply.code(403).send({ error: 'Forbidden' });
});

app.get('/health', async () => ({ ok: true }));

await app.register(authRoutes);
await app.register(tripRoutes);
await app.register(trackingRoutes);

// WebSocket: ws://host:3000/ws?token=<JWT>&trip_id=<ID>
app.get('/ws', { websocket: true }, async (socket, req) => {
  let user;
  try {
    user = app.jwt.verify(String(req.query.token || ''));
  } catch {
    return socket.close(4401, 'Unauthorized');
  }

  const tripId = Number(req.query.trip_id);
  const trip = Number.isInteger(tripId)
    ? await prisma.trip.findUnique({ where: { id: tripId }, include: tripInclude })
    : null;
  if (!trip || !canAccess(user, trip)) return socket.close(4403, 'Forbidden');

  join(tripId, socket);
  socket.on('close', () => leave(tripId, socket));
  socket.on('error', () => leave(tripId, socket));

  // Send the current state right away so the map isn't empty.
  socket.send(JSON.stringify({
    event: 'snapshot',
    trip_id: trip.id,
    status: trip.status,
    latitude: trip.driver?.lastLatitude ?? null,
    longitude: trip.driver?.lastLongitude ?? null,
    last_update: trip.driver?.lastLocationAt ?? null,
    ...progress(trip, trip.driver?.lastLatitude, trip.driver?.lastLongitude),
  }));
});

const port = Number(process.env.PORT) || 3000;
await app.listen({ port, host: '0.0.0.0' });

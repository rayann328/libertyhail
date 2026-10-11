// Tracks which WebSocket clients are watching which trip.
const rooms = new Map(); // tripId -> Set<socket>

export function join(tripId, socket) {
  if (!rooms.has(tripId)) rooms.set(tripId, new Set());
  rooms.get(tripId).add(socket);
}

export function leave(tripId, socket) {
  const set = rooms.get(tripId);
  if (!set) return;
  set.delete(socket);
  if (set.size === 0) rooms.delete(tripId);
}

export function broadcast(tripId, payload) {
  const set = rooms.get(tripId);
  if (!set) return;
  const msg = JSON.stringify(payload);
  for (const s of set) {
    if (s.readyState === 1) s.send(msg);
  }
}

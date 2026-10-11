# LibertyHail

Real-time vehicle tracking and ride management. A customer requests a ride, a driver is assigned automatically, and the customer follows the car live on a map with ETA and trip status.

The repository has two parts:

| Folder | What it is |
| --- | --- |
| `libertyhail-backend` | REST API and WebSocket server (Fastify, Prisma, PostgreSQL) |
| `libertyhail_app` | One Flutter app with two experiences: customer and driver |

## Features

**Customer**
- Register and log in
- Pick a destination on the map and request a ride (the nearest available driver is assigned)
- Live car position, ETA, distance, driver and vehicle details
- Real-time trip status updates and trip cancellation
- Trip history

**Driver**
- Log in, go online or offline
- Sends GPS position every 3 seconds
- Moves the trip through its statuses with one button per step, plus an Emergency button
- Demo mode that simulates the car driving to the pickup and destination

**Backend**
- JWT authentication with roles (customer, driver)
- Trip-level authorization: a customer only sees their own trip, a driver only theirs
- Trip lifecycle with validated transitions and a status history
- Location history per trip
- Notifications stored in the database and device registration for push tokens
- Rate limiting on all routes, stricter on login

## Trip lifecycle

```
ASSIGNED -> EN_ROUTE_TO_PICKUP -> ARRIVED -> PASSENGER_ONBOARD -> EN_ROUTE_TO_DESTINATION -> COMPLETED
```
`EMERGENCY` can be raised from any active status, and a trip can be `CANCELLED` before the passenger is on board.

## Tech stack

- **Backend:** Node.js 20.6+, Fastify 5, Prisma 6, PostgreSQL, `@fastify/websocket`, `@fastify/jwt`
- **App:** Flutter, `flutter_map` with OpenStreetMap (no API key needed), `geolocator`, `web_socket_channel`
- **Database:** any PostgreSQL (a local Docker container or a hosted one such as Neon)

## Run it locally

### 1. Backend

```bash
cd libertyhail-backend
cp .env.example .env        # Windows: copy .env.example .env
```

Edit `.env`:
- `DATABASE_URL`: your PostgreSQL connection string. For a local database run `docker compose up -d` and keep the default value. Otherwise paste the connection string from your hosted database.
- `JWT_SECRET`: any long random string.

```bash
npm install
npx prisma db push          # creates the tables
npm run seed                # creates the test accounts
npm run dev                 # http://localhost:3000
```

Check `http://localhost:3000/health`. It should return `{"ok":true}`.

Test accounts (password `123456` for both): `customer@test.com` and `driver@test.com`.

### 2. Flutter app

```bash
cd libertyhail_app
flutter pub get
```

Open `lib/config.dart` and set `serverHost` to the address of the machine running the backend, for example `192.168.0.104:3000`. A real phone must be on the same Wi-Fi network, and a VPN can block the connection.

```bash
flutter run
```

## Demo (two devices or two windows)

1. **Driver:** run the app (for example `flutter run -d chrome`), log in as `driver@test.com`, switch **Online** on and turn on **Simulate movement**.
2. **Customer:** run the app on a phone or another window, log in as `customer@test.com`, tap the map to set a destination and press **Request ride**.
3. **Driver:** the trip appears within a few seconds. Press the status buttons in order.
4. **Customer:** watch the car move and the status change live. Afterwards the trip appears in the history.

Do not open both roles in two tabs of the same browser, because they share the login session.

## API overview

All routes except register and login need `Authorization: Bearer <token>`.

| Method | Route | Role | Purpose |
| --- | --- | --- | --- |
| POST | `/api/auth/register` | public | Create a customer account |
| POST | `/api/auth/login` | public | Log in |
| GET | `/api/auth/me` | any | Current user |
| POST | `/api/trips` | customer | Request a ride |
| GET | `/api/trips` | any | My trips |
| GET | `/api/trips/active/me` | customer | Current active trip |
| GET | `/api/trips/:id` | participant | Trip details with ETA |
| PATCH | `/api/trips/:id/status` | driver | Change trip status |
| POST | `/api/trips/:id/cancel` | participant | Cancel a trip |
| GET | `/api/trips/:id/location` | participant | Last known vehicle position |
| GET | `/api/trips/:id/location/history` | participant | Recorded route |
| POST | `/api/drivers/location` | driver | Send GPS position |
| PATCH | `/api/drivers/me/status` | driver | Go online or offline |
| GET | `/api/drivers/me/active-trip` | driver | Current assigned trip |
| GET | `/api/notifications` | any | My notifications |
| POST | `/api/notifications/:id/read` | any | Mark as read |
| POST | `/api/devices` | any | Register a push token |

**WebSocket:** `ws://HOST:3000/ws?token=<JWT>&trip_id=<ID>`

Events sent to the client: `snapshot` (on connect), `vehicle.location.updated` and `trip.status.updated`.

## Known limitations

This is an MVP. These items are not implemented yet:
- Actual push delivery through Firebase Cloud Messaging (notifications are stored and device tokens are registered)
- OTP login (email and password are used)
- Dispatcher and admin dashboards
- Redis for location caching (the last position is stored on the driver record)
- ETA uses straight-line distance at an assumed average speed, not real routing

## Project structure

```
libertyhail-backend/
  prisma/schema.prisma      database schema
  prisma/seed.js            test accounts
  src/server.js             app setup, auth hooks, WebSocket endpoint
  src/routes/               auth, trips, tracking
  src/lib.js                trip transitions, ETA, notifications
  src/hub.js                WebSocket rooms per trip
libertyhail_app/
  lib/main.dart             entry point
  lib/login.dart            login and registration
  lib/customer.dart         customer map, tracking, history
  lib/driver.dart           driver controls and GPS sending
  lib/api.dart              HTTP client
  lib/config.dart           server address
```

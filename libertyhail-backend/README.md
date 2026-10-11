# LibertyHail Backend (MVP)

Fastify + Prisma + PostgreSQL + WebSocket

## تشغيل (5 أوامر)
```bash
cp .env.example .env          # (Windows: copy .env.example .env)
docker compose up -d          # يشغل PostgreSQL
npm install
npx prisma db push            # ينشئ الجداول
npm run seed                  # مستخدمين تجريبيين
npm run dev                   # السيرفر على http://localhost:3000
```
حسابات تجريبية (كلمة السر 123456): customer@test.com و driver@test.com

## اختبار سريع (curl)
```bash
# 1) دخول الزبون والسائق
curl -s localhost:3000/api/auth/login -H 'content-type: application/json' -d '{"email":"customer@test.com","password":"123456"}'
curl -s localhost:3000/api/auth/login -H 'content-type: application/json' -d '{"email":"driver@test.com","password":"123456"}'

# 2) الزبون يطلب رحلة (حط التوكن مكان CUSTOMER_TOKEN)
curl -s localhost:3000/api/trips -H 'content-type: application/json' -H 'authorization: Bearer CUSTOMER_TOKEN' \
  -d '{"pickup_latitude":33.8938,"pickup_longitude":35.5018,"destination_latitude":33.9,"destination_longitude":35.55}'

# 3) تتبع حي (ثبّت wscat: npm i -g wscat)
wscat -c "ws://localhost:3000/ws?token=CUSTOMER_TOKEN&trip_id=1"

# 4) السائق يرسل موقع ويغيّر الحالة
curl -s localhost:3000/api/drivers/location -H 'content-type: application/json' -H 'authorization: Bearer DRIVER_TOKEN' \
  -d '{"latitude":33.895,"longitude":35.51,"speed":8}'
curl -s -X PATCH localhost:3000/api/trips/1/status -H 'content-type: application/json' -H 'authorization: Bearer DRIVER_TOKEN' \
  -d '{"status":"EN_ROUTE_TO_PICKUP"}'
```
تسلسل الحالات: ASSIGNED → EN_ROUTE_TO_PICKUP → ARRIVED → PASSENGER_ONBOARD → EN_ROUTE_TO_DESTINATION → COMPLETED

import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcryptjs';

const prisma = new PrismaClient();
const hash = await bcrypt.hash('123456', 10);

await prisma.user.upsert({
  where: { email: 'customer@test.com' },
  update: {},
  create: { name: 'Test Customer', email: 'customer@test.com', phone: '70000001', passwordHash: hash, role: 'customer' },
});

const driverUser = await prisma.user.upsert({
  where: { email: 'driver@test.com' },
  update: {},
  create: { name: 'Test Driver', email: 'driver@test.com', phone: '70000002', passwordHash: hash, role: 'driver' },
});

const driver = await prisma.driver.upsert({
  where: { userId: driverUser.id },
  update: {},
  create: {
    userId: driverUser.id,
    licenseNumber: 'LB-12345',
    status: 'AVAILABLE',
    lastLatitude: 33.8938,
    lastLongitude: 35.5018,
    lastLocationAt: new Date(),
  },
});

await prisma.vehicle.upsert({
  where: { plateNumber: 'B 123456' },
  update: {},
  create: { driverId: driver.id, plateNumber: 'B 123456', make: 'Toyota', model: 'Corolla', year: 2020, color: 'White' },
});

console.log('Seed done: customer@test.com / driver@test.com  (password: 123456)');
await prisma.$disconnect();

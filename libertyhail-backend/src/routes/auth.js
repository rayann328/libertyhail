import bcrypt from 'bcryptjs';
import { prisma } from '../db.js';

export async function authRoutes(app) {
  app.post('/api/auth/register', {
    schema: {
      body: {
        type: 'object',
        required: ['name', 'email', 'password'],
        properties: {
          name: { type: 'string', minLength: 1 },
          email: { type: 'string', format: 'email' },
          password: { type: 'string', minLength: 6 },
          phone: { type: 'string' },
        },
      },
    },
  }, async (req, reply) => {
    const { name, email, password, phone } = req.body;
    const exists = await prisma.user.findUnique({ where: { email: email.toLowerCase() } });
    if (exists) return reply.code(409).send({ error: 'Email already registered' });
    const user = await prisma.user.create({
      data: { name, email: email.toLowerCase(), phone, passwordHash: await bcrypt.hash(password, 10), role: 'customer' },
    });
    const token = app.jwt.sign({ id: user.id, role: user.role }, { expiresIn: '7d' });
    return reply.code(201).send({ token, user: { id: user.id, name: user.name, email: user.email, role: user.role } });
  });

  app.post('/api/auth/login', {
    config: { rateLimit: { max: 10, timeWindow: '1 minute' } },
    schema: {
      body: {
        type: 'object',
        required: ['email', 'password'],
        properties: { email: { type: 'string' }, password: { type: 'string' } },
      },
    },
  }, async (req, reply) => {
    const { email, password } = req.body;
    const user = await prisma.user.findUnique({ where: { email: email.toLowerCase() } });
    if (!user || user.status !== 'active' || !(await bcrypt.compare(password, user.passwordHash))) {
      return reply.code(401).send({ error: 'Invalid email or password' });
    }
    const token = app.jwt.sign({ id: user.id, role: user.role }, { expiresIn: '7d' });
    return { token, user: { id: user.id, name: user.name, email: user.email, role: user.role } };
  });

  app.get('/api/auth/me', { preHandler: [app.auth] }, async (req) => {
    const user = await prisma.user.findUnique({
      where: { id: req.user.id },
      select: { id: true, name: true, email: true, phone: true, role: true },
    });
    return { user };
  });
}

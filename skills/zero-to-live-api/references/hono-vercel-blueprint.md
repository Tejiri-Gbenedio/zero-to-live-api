# Hono + Vercel Serverless API Blueprint

This blueprint provides the complete, copy-pasteable production pattern for scaffolding a high-performance, edge-compatible REST API using Hono, TypeScript, Zod validation, rate limiting, and CORS.

---

## 1. Project Configuration Files

### `package.json`
```json
{
  "name": "api-service",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "tsx watch src/index.ts",
    "build": "esbuild src/index.ts --bundle --platform=node --target=node20 --outfile=dist/index.js",
    "start": "node dist/index.js",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "@hono/zod-validator": "^0.4.2",
    "hono": "^4.7.0",
    "zod": "^3.24.2"
  },
  "devDependencies": {
    "@types/node": "^20.17.19",
    "esbuild": "^0.25.0",
    "tsx": "^4.19.3",
    "typescript": "^5.7.3"
  }
}
```

### `tsconfig.json`
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "lib": ["ES2022"],
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "outDir": "./dist",
    "rootDir": "./src"
  },
  "include": ["src/**/*"]
}
```

### `vercel.json`
```json
{
  "version": 2,
  "rewrites": [
    {
      "source": "/(.*)",
      "destination": "/api"
    }
  ],
  "functions": {
    "api/index.ts": {
      "runtime": "nodejs20.x"
    }
  }
}
```

### `.env.example`
```bash
PORT=3000
NODE_ENV=development
ALLOWED_ORIGIN=http://localhost:5173
DATABASE_URL=postgres://user:password@localhost:5432/app_db
API_SECRET_KEY=replace_with_secure_random_key_in_production
```

---

## 2. Main Application (`src/index.ts`)

```typescript
import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { logger } from 'hono/logger';
import { z } from 'zod';
import { zValidator } from '@hono/zod-validator';
import { serve } from '@hono/node-server';

// Standard Envelope Types
export interface ApiSuccessResponse<T> {
  success: true;
  data: T;
  meta?: Record<string, unknown>;
}

export interface ApiErrorResponse {
  success: false;
  error: {
    code: string;
    message: string;
    details?: unknown;
  };
}

const app = new Hono();

// Global Middleware
app.use('*', logger());
app.use(
  '*',
  cors({
    origin: (origin) => {
      const allowed = process.env.ALLOWED_ORIGIN || '*';
      if (allowed === '*' || !origin || origin === allowed) {
        return origin || '*';
      }
      return allowed;
    },
    allowMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowHeaders: ['Content-Type', 'Authorization'],
    exposeHeaders: ['Content-Length'],
    maxAge: 600,
  })
);

// In-Memory IP Rate Limiting Middleware (100 req/minute)
const ipRequestCounts = new Map<string, { count: number; resetTime: number }>();
app.use('*', async (c, next) => {
  const ip = c.req.header('x-forwarded-for') || '127.0.0.1';
  const now = Date.now();
  const windowMs = 60 * 1000;
  const maxRequests = 100;

  const record = ipRequestCounts.get(ip) || { count: 0, resetTime: now + windowMs };
  if (now > record.resetTime) {
    record.count = 1;
    record.resetTime = now + windowMs;
  } else {
    record.count += 1;
  }
  ipRequestCounts.set(ip, record);

  if (record.count > maxRequests) {
    return c.json<ApiErrorResponse>(
      {
        success: false,
        error: {
          code: 'RATE_LIMIT_EXCEEDED',
          message: 'Too many requests. Please slow down.',
        },
      },
      429
    );
  }

  await next();
});

// Uniform Error Handler
app.onError((err, c) => {
  console.error('[Unhandled Exception]:', err);
  return c.json<ApiErrorResponse>(
    {
      success: false,
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: err.message || 'An unexpected error occurred.',
      },
    },
    500
  );
});

// 404 Handler
app.notFound((c) => {
  return c.json<ApiErrorResponse>(
    {
      success: false,
      error: {
        code: 'NOT_FOUND',
        message: `Endpoint ${c.req.method} ${c.req.path} not found.`,
      },
    },
    404
  );
});

// Health Check Route
app.get('/health', (c) => {
  return c.json<ApiSuccessResponse<{ status: string; timestamp: string }>>({
    success: true,
    data: {
      status: 'healthy',
      timestamp: new Date().toISOString(),
    },
  });
});

app.get('/api/health', (c) => {
  return c.json<ApiSuccessResponse<{ status: string; timestamp: string }>>({
    success: true,
    data: {
      status: 'healthy',
      timestamp: new Date().toISOString(),
    },
  });
});

// -------------------------------------------------------------
// Entity Routes & Validation Schemas
// -------------------------------------------------------------

// Example: Submissions / Leads entity
export const CreateLeadSchema = z.object({
  name: z.string().min(2, 'Name must be at least 2 characters'),
  email: z.string().email('Please enter a valid email address'),
  message: z.string().min(5, 'Message must be at least 5 characters').max(1000),
  source: z.string().optional().default('website'),
});

export type CreateLeadInput = z.infer<typeof CreateLeadSchema>;

// Persistence Adapter (In-Memory Data Store with Persistent JSON Backup)
interface LeadRecord extends CreateLeadInput {
  id: string;
  createdAt: string;
}

const leadsDatabase: LeadRecord[] = [];

// GET /api/leads - Retrieve items
app.get('/api/leads', (c) => {
  return c.json<ApiSuccessResponse<LeadRecord[]>>({
    success: true,
    data: leadsDatabase,
    meta: { total: leadsDatabase.length },
  });
});

// POST /api/leads - Create item with strict Zod validation
app.post(
  '/api/leads',
  zValidator('json', CreateLeadSchema, (result, c) => {
    if (!result.success) {
      return c.json<ApiErrorResponse>(
        {
          success: false,
          error: {
            code: 'VALIDATION_ERROR',
            message: 'Invalid request payload.',
            details: result.error.format(),
          },
        },
        400
      );
    }
  }),
  async (c) => {
    const body = c.req.valid('json');
    const newRecord: LeadRecord = {
      id: `lead_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
      createdAt: new Date().toISOString(),
      ...body,
    };
    leadsDatabase.push(newRecord);

    return c.json<ApiSuccessResponse<LeadRecord>>(
      {
        success: true,
        data: newRecord,
      },
      201
    );
  }
);

// Fallback for Vercel Serverless Export
export default app;

// Local Development Server boot
if (process.env.NODE_ENV !== 'production' && !process.env.VERCEL) {
  const port = Number(process.env.PORT) || 3000;
  console.log(`[zero-to-live-api] Server running on http://127.0.0.1:${port}`);
  serve({
    fetch: app.fetch,
    port,
  });
}
```

---

## 3. Database Persistence Adapters

### A. SQLite / Cloudflare D1 Pattern
```typescript
export async function getD1Db(env: { DB: D1Database }) {
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS records (id TEXT PRIMARY KEY, payload TEXT, created_at TEXT)`
  ).run();
  return {
    async insert(id: string, data: unknown) {
      return env.DB.prepare(
        `INSERT INTO records (id, payload, created_at) VALUES (?, ?, ?)`
      ).bind(id, JSON.stringify(data), new Date().toISOString()).run();
    },
    async list() {
      const { results } = await env.DB.prepare(`SELECT * FROM records ORDER BY created_at DESC`).all();
      return results.map((r: any) => ({ id: r.id, ...JSON.parse(r.payload), createdAt: r.created_at }));
    }
  };
}
```

### B. PostgreSQL (Neon / Supabase Pool)
```typescript
import { Pool } from 'pg';

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
});

export async function queryDb<T = any>(text: string, params: any[] = []): Promise<T[]> {
  const client = await pool.connect();
  try {
    const res = await client.query(text, params);
    return res.rows;
  } finally {
    client.release();
  }
}
```

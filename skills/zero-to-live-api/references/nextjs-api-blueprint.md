# Next.js App Router API Blueprint

This blueprint provides the complete, copy-pasteable production pattern for Next.js App Router (`app/api/.../route.ts`) backends with strict Zod validation, standardized response envelopes, in-memory rate limiting, and CORS support.

---

## 1. Response Helper & Standard Envelope (`src/lib/api-response.ts`)

```typescript
import { NextResponse } from 'next/server';

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

export const corsHeaders = {
  'Access-Control-Allow-Origin': process.env.ALLOWED_ORIGIN || '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

export function apiSuccess<T>(data: T, status = 200, meta?: Record<string, unknown>) {
  return NextResponse.json<ApiSuccessResponse<T>>(
    {
      success: true,
      data,
      ...(meta ? { meta } : {}),
    },
    {
      status,
      headers: corsHeaders,
    }
  );
}

export function apiError(code: string, message: string, status = 400, details?: unknown) {
  return NextResponse.json<ApiErrorResponse>(
    {
      success: false,
      error: {
        code,
        message,
        ...(details ? { details } : {}),
      },
    },
    {
      status,
      headers: corsHeaders,
    }
  );
}
```

---

## 2. In-Memory Sliding Window Rate Limiter (`src/lib/rate-limiter.ts`)

```typescript
interface RateLimitRecord {
  count: number;
  resetAt: number;
}

const rateLimitStore = new Map<string, RateLimitRecord>();

export function checkRateLimit(identifier: string, limit = 60, windowSeconds = 60): { allowed: boolean; remaining: number } {
  const now = Date.now();
  const windowMs = windowSeconds * 1000;
  const existing = rateLimitStore.get(identifier);

  if (!existing || now > existing.resetAt) {
    rateLimitStore.set(identifier, { count: 1, resetAt: now + windowMs });
    return { allowed: true, remaining: limit - 1 };
  }

  if (existing.count >= limit) {
    return { allowed: false, remaining: 0 };
  }

  existing.count += 1;
  return { allowed: true, remaining: limit - existing.count };
}
```

---

## 3. Entity Validation Schema (`src/lib/validations/records.ts`)

```typescript
import { z } from 'zod';

export const CreateRecordSchema = z.object({
  title: z.string().min(2, 'Title must be at least 2 characters').max(120),
  description: z.string().optional().default(''),
  category: z.enum(['general', 'support', 'billing', 'feedback']).default('general'),
  priority: z.number().int().min(1).max(5).default(3),
});

export type CreateRecordInput = z.infer<typeof CreateRecordSchema>;
```

---

## 4. Route Handlers: Collection CRUD (`app/api/records/route.ts`)

```typescript
import { NextRequest, NextResponse } from 'next/server';
import { apiSuccess, apiError, corsHeaders } from '@/lib/api-response';
import { checkRateLimit } from '@/lib/rate-limiter';
import { CreateRecordSchema } from '@/lib/validations/records';

export const dynamic = 'force-dynamic';

// In-Memory store fallback
interface RecordItem {
  id: string;
  title: string;
  description: string;
  category: string;
  priority: number;
  createdAt: string;
}

const recordsDatabase: RecordItem[] = [];

// Preflight CORS handler
export async function OPTIONS() {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders,
  });
}

// GET /api/records - List records
export async function GET(request: NextRequest) {
  try {
    const ip = request.headers.get('x-forwarded-for') || '127.0.0.1';
    const { allowed } = checkRateLimit(ip, 100, 60);

    if (!allowed) {
      return apiError('RATE_LIMIT_EXCEEDED', 'Too many requests. Please wait a moment.', 429);
    }

    const { searchParams } = new URL(request.url);
    const category = searchParams.get('category');

    let filtered = recordsDatabase;
    if (category) {
      filtered = filtered.filter((r) => r.category === category);
    }

    return apiSuccess(filtered, 200, { total: filtered.length });
  } catch (error: any) {
    console.error('[GET /api/records Error]:', error);
    return apiError('INTERNAL_ERROR', error.message || 'Failed to retrieve records', 500);
  }
}

// POST /api/records - Create record
export async function POST(request: NextRequest) {
  try {
    const ip = request.headers.get('x-forwarded-for') || '127.0.0.1';
    const { allowed } = checkRateLimit(ip, 60, 60);

    if (!allowed) {
      return apiError('RATE_LIMIT_EXCEEDED', 'Request quota exceeded.', 429);
    }

    let rawBody;
    try {
      rawBody = await request.json();
    } catch {
      return apiError('MALFORMED_JSON', 'Request body must be valid JSON.', 400);
    }

    // Strict Zod Validation
    const validationResult = CreateRecordSchema.safeParse(rawBody);
    if (!validationResult.success) {
      return apiError(
        'VALIDATION_FAILED',
        'One or more input fields are invalid.',
        400,
        validationResult.error.flatten().fieldErrors
      );
    }

    const validData = validationResult.data;
    const newRecord: RecordItem = {
      id: `rec_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`,
      ...validData,
      createdAt: new Date().toISOString(),
    };

    recordsDatabase.push(newRecord);
    return apiSuccess(newRecord, 201);
  } catch (error: any) {
    console.error('[POST /api/records Error]:', error);
    return apiError('INTERNAL_ERROR', error.message || 'Internal server error', 500);
  }
}
```

---

## 5. Health Check Route (`app/api/health/route.ts`)

```typescript
import { apiSuccess, corsHeaders } from '@/lib/api-response';
import { NextResponse } from 'next/server';

export const dynamic = 'force-dynamic';

export async function OPTIONS() {
  return new NextResponse(null, { status: 204, headers: corsHeaders });
}

export async function GET() {
  return apiSuccess({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    runtime: 'nextjs-app-router',
  });
}
```


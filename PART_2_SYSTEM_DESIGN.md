# Part 2: System Design Document — Scaling Datastraw CX Copilot

## 1. System Architecture Diagram

```mermaid
flowchart TB
    subgraph Channels["External Channels & E-Commerce"]
        WA["Meta WhatsApp Business API"]
        IG["Instagram DM / Email / Zendesk"]
        SHOP["Shopify / WooCommerce / ERP"]
    end

    subgraph Edge["Ingestion & Edge Layer"]
        GW["API Gateway / Webhook Receiver\n(HMAC Signature + Rate Limiting)"]
        REDIS_IDEM[("Redis\nIdempotency & Deduplication Cache")]
        QUEUE[["Durable Event Queue\n(BullMQ / AWS SQS - Tenant Sharded)"]]
    end

    subgraph Core["Stateless Core & Orchestration Services"]
        INGEST["Ingestion Workers\n(Deduplication + Order Sync)"]
        API["Core CX Backend API\n(Node.js / Supabase Edge)"]
        AI_SVC["AI Copilot & Guardrail Service"]
        OUTBOX["Transactional Outbox Worker\n(Reliable Outbound Delivery)"]
    end

    subgraph Data["Multi-Tenant Storage Layer (Strict Brand Isolation)"]
        PG[("PostgreSQL + PgBouncer\n(Row-Level Security by brand_id)")]
        QDRANT[("Qdrant Vector DB\n(Tenant-Partitioned Payload Index)")]
    end

    subgraph LLM_Gateway["Resilient AI Gateway"]
        OR["OpenRouter Primary\n(GPT-4o-mini / Claude Haiku)"]
        DI["DeepInfra Fallback\n(Llama-3.3-70B)"]
    end

    subgraph Client["Agent Frontend (5,000 Concurrent CX Agents)"]
        SPA["React Workspace SPA\n(Supabase Realtime WebSockets)"]
    end

    WA & IG -->|Webhooks| GW
    GW <-->|Check Message_ID| REDIS_IDEM
    GW -->|Enqueue <50ms| QUEUE
    QUEUE --> INGEST
    INGEST <-->|Fetch Order Context\n(3s Timeout + Circuit Breaker)| SHOP
    INGEST -->|Write Message & Context| PG
    PG -.->|Realtime WebSocket Push| SPA
    SPA <-->|JWT with authorized brand_ids| API
    API --> AI_SVC
    AI_SVC <-->|Hybrid Search + brand_id Filter| QDRANT
    AI_SVC <-->|Policy + Chat Context| OR
    OR -.->|Automatic Failover| DI
    API -->|Write PENDING Outbox| PG
    PG --> OUTBOX
    OUTBOX -->|Deliver Reply + Exponential Backoff| WA & IG
```

---

## 2. End-to-End Architecture Overview

To support **500 brands, 5,000 concurrent CX agents, and millions of customer messages**, the system decouples high-throughput message ingestion from interactive agent workflows and LLM generation.

1. **Frontend:** React SPA built with Next.js, subscribing to real-time ticket updates over WebSockets (`Supabase Realtime`) scoped to the agent's active brand queue. Employs optimistic UI updates, response drafting autosave in `localStorage`, and virtualized message lists to render long chat histories smoothly without DOM bloat.
2. **Ingestion & Queues:** External webhooks (Meta WhatsApp, Instagram, Email) hit a lightweight Edge Webhook Receiver that verifies HMAC signatures, checks Redis for idempotency (`SET message_id NX EX 86400`), pushes the raw event to a tenant-sharded queue (BullMQ / AWS SQS), and immediately returns `200 OK` within 50ms to satisfy strict webhook timeouts.
3. **Database Layer:** Supabase PostgreSQL fronted by `PgBouncer` for connection pooling, utilizing monthly range partitioning on `messages` and `ai_logs` tables to sustain millions of records without query degradation.
4. **Authentication & Authorization:** Supabase Auth issues short-lived JWTs containing custom claims (`user_id`, `role`, `authorized_brand_ids`). All incoming requests are validated at the edge middleware before hitting backend services.

---

## 3. Multi-Brand Data Isolation (Zero Cross-Tenant Leakage)

Preventing Brand A from ever accessing Brand B's conversations or Knowledge Base is enforced via three independent layers (**Defense-in-Depth**):

1. **API & Middleware Layer:** Every API request extracts the authenticated user's `authorized_brand_ids` from their verified JWT (never trusting client-supplied headers alone) and rejects unauthorized brand scopes with `403 Forbidden`.
2. **Database Layer (PostgreSQL Row-Level Security):** Every table (`conversations`, `messages`, `knowledge_base`, `ai_logs`) contains a mandatory `brand_id` column governed by a PostgreSQL RLS Policy:
   ```sql
   CREATE POLICY tenant_isolation ON knowledge_base
   USING (brand_id = current_setting('app.current_brand_id')::uuid);
   ```
   Even if an engineer writes an ad-hoc query missing a `WHERE brand_id = ...` clause, PostgreSQL physically blocks cross-brand rows at the database engine level.
3. **Vector Search Layer (Qdrant Tenant Partitioning):** In Qdrant, all vectors store `brand_id` in their metadata indexed with `is_tenant: true`. The retrieval service wraps the Qdrant client so every query enforces a mandatory pre-filter before vector scoring:
   ```json
   {
     "filter": {
       "must": [
         { "key": "brand_id", "match": { "value": "active_brand_id" } }
       ]
     }
   }
   ```

---

## 4. Reliable AI & RAG Architecture

1. **Hybrid Retrieval (Dense + Sparse RRF):** At scale (hundreds of SOPs and SKU manuals per brand), pure dense vector search struggles with exact SKU codes and numeric timelines (e.g. "48 hours" vs "7 days"). We combine Qdrant dense vector search with BM25 sparse keyword search, fused via **Reciprocal Rank Fusion (RRF)** to pass the top 4 chunks to the LLM.
2. **Hallucination Prevention & Context Assembly:** The prompt strictly isolates:
   - System Guardrails (Zero-Tolerance Rules)
   - Verified Order Context (`Days Since Delivery`, Status)
   - Retrieved Brand KB Chunks
   Temperature is pinned to `0.1`, and the LLM is forced to output structured JSON containing `guardrail_status` (`APPROVED_BY_POLICY` | `POLICY_RESTRICTION` | `MISSING_KB_INFO`), `reasoning`, and `suggested_reply`.
3. **Confidence & Fallbacks:** If retrieval similarity scores fall below 0.70 or the model outputs `MISSING_KB_INFO`, the UI disables one-click sending, highlights the missing policy in red, and prompts the agent to escalate.
4. **Continuous Evaluation:** We log `ai_generated_response`, `agent_edited_response`, and `final_response`. Computing the **Agent Edit Rate & Levenshtein Edit Distance** per brand gives us an automated production KPI: if agents heavily rewrite AI drafts for a specific brand, it automatically alerts operations that the brand's KB articles are outdated.

---

## 5. Scalability: Scaling from 20 to 500 Brands

### What Breaks First:
1. **Noisy-Neighbor Queue Starvation:** One D2C brand running a midnight flash sale can flood the shared webhook queue with 100,000 WhatsApp messages, delaying real-time chat for the other 499 brands.
2. **PostgreSQL Connection & Index Contention:** 5,000 agents polling + high-velocity message writes will exhaust Postgres connections and bloat B-tree indexes.

### What We Change:
- **Tenant-Sharded Fair Queues:** Partition worker queues by `brand_id` hash with per-brand concurrency caps so a traffic spike on Brand A never degrades latency for Brand B.
- **PgBouncer + Read Replicas + Table Partitioning:** Route analytics and audit reads to read replicas, pool transactional connections via PgBouncer in transaction mode, and partition `messages` and `ai_logs` monthly.

---

## 6. Reliability & Failure Handling

| Failure Scenario | Architectural Remedy |
| :--- | :--- |
| **Webhook received twice** | Meta WhatsApp uses at-least-once delivery. We extract `wamid` and execute `SET resource_id NX EX 86400` in Redis plus a `UNIQUE(brand_id, external_message_id)` constraint in Postgres. Duplicate deliveries return `200 OK` and exit immediately. |
| **External Order API times out** | Order enrichment calls use a strict 2.5-second timeout and a Circuit Breaker (resilience4j pattern). If the brand's Shopify/ERP API times out, we fall back to the last synced order snapshot in Postgres and display a warning badge: *"Live order status delayed — showing cached data from 2h ago"*. |
| **AI request fails** | Our AI Gateway wraps OpenRouter with a 6-second timeout, 1 jittered retry, and automatic failover to DeepInfra (`Llama-3.3-70B`). If all providers fail, the UI gracefully degrades to brand-specific quick-reply macros so the agent is never blocked. |
| **Message processed, but response wasn't sent** | We implement the **Transactional Outbox Pattern**. Clicking "Send" saves the message in Postgres with status `PENDING_DISPATCH` and inserts an outbox job in the same DB transaction. A background worker delivers the payload to the Meta WhatsApp API; if delivery fails after 3 exponential backoff retries, the message status flips to `FAILED_TO_SEND` and alerts the agent in real time with a `[Retry Send]` button. |

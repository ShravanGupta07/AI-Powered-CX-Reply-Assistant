# AI Usage Reflection

## 1. Which AI tools did you use?
- **LLM Frontier Models (Claude 3.5 Sonnet & Gemini):** Used for architectural brainstorming, reviewing multi-tenant RLS trade-offs, and initial boilerplate scaffolding.
- **AI Coding Assistants (Cursor / Copilot):** Used for TypeScript autocomplete, Tailwind CSS utility class combinations, and syntax structuring.

---

## 2. How did you use them? (3 Concrete Examples)

### Example 1: Database Seed Schema for Contrasting Brand Boundaries
- **Prompting & Usage:** Prompted the model to craft SQL seed statements modeling two contrasting brands with polar-opposite CX refund and return policies (*Aura Botanics* with a strict 7-day refund window and 48-hour broken bottle replacement policy vs. *Titan Gear* with an open 30-day no-questions-asked refund window).
- **Outcome:** Provided realistic test scenario data (`schema.sql`) that immediately exposes cross-tenant leakage or hallucinated policy overrides.

### Example 2: Tailwind CSS 3-Pane Layout Generation
- **Prompting & Usage:** Used Copilot to generate responsive flex and grid layouts for the 3-pane CX Agent Workspace (left conversation navigation, center chat history with order context banner, right AI copilot drawer).
- **Outcome:** Accelerated frontend styling and ensured high density and readability for CX agents.

### Example 3: Structured JSON Prompt Construction for OpenRouter
- **Prompting & Usage:** Designed and refined the zero-hallucination system prompt to force OpenRouter (`gpt-4o-mini`) to return a strict JSON schema containing `guardrail_status`, `reasoning`, and `suggested_reply`.
- **Outcome:** Allowed the frontend to reliably display color-coded guardrail badges (Green, Amber, Red) with policy rationale.

---

## 3. What did AI get wrong, and how did you fix it?

### The Issue:
When generating the initial Knowledge Base retrieval query and system prompt, the AI assistant made two dangerous architectural mistakes:
1. **Cross-Tenant Leakage Risk:** It initially proposed querying the `knowledge_base` table using a general semantic similarity search *across all brands*, intending to filter the top 10 results by brand in memory afterward. For a multi-tenant CX platform, this created a critical vector for cross-tenant data leakage if the in-memory filter failed or was bypassed.
2. **Hallucinated "Helpful" Exceptions:** In the system prompt, the AI defaulted to standard conversational helpfulness. When tested with a customer asking for a refund 20 days after delivery under a 7-day policy, the model hallucinated an unapproved policy exception, promising the customer a *"one-time complimentary store credit of 50%"* that was never defined in the brand's Knowledge Base.

### The Fix:
1. **Strict SQL Tenant Isolation:** Enforced hard database scoping (`.eq('brand_id', conv.brand_id)`) at the query level before any retrieval scoring occurs, ensuring Brand B's data can never exist in Brand A's memory space.
2. **Deterministic 3-State Guardrail Prompt:** Re-engineered the system prompt with strict negative constraints forbidding the invention of discounts, store credits, or timeline extensions not explicitly present in the KB. Introduced the explicit `guardrail_status` enum (`APPROVED_BY_POLICY`, `POLICY_RESTRICTION`, `MISSING_KB_INFO`) so any expired timeline triggers an explicit policy restriction alert to the agent rather than a hallucinated promise.

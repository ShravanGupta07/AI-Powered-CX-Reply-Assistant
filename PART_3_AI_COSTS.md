# Part 3: Technical Problem Solving — AI Cost Spike

## Scenario
> Datastraw's AI costs have increased from ₹20,000/month to ₹1,00,000/month over three months (a 5x increase / +400%), while the number of customer conversations only increased by approximately 40% (1.4x).

---

## 1. Diagnosis Framework

Because conversation volume grew by 1.4x while AI spend grew by 5x, our average cost per conversation escalated by **~3.57x**. Before altering production code or renegotiating vendor agreements, I would extract telemetry from `ai_logs` and OpenRouter usage metrics across the last 90 days, sliced by `brand_id`, `model`, `prompt_tokens`, and `completion_tokens`. 

I would test three primary hypotheses:

### Hypothesis 1: Context Window Stuffing & Chat History Bloat (Token Multiplier)
- **Investigation:** Check `prompt_tokens` trend line over the 3-month window.
- **Root Cause:** If code was passing the entire raw chat history (e.g. 30–50 turns) and dumping the entire brand Knowledge Base into the system prompt instead of using top-k semantic retrieval and a sliding 6-turn message window, input tokens per call expand linearly with chat length.

### Hypothesis 2: Eager Pre-Generation on Every Webhook (Call Multiplier)
- **Investigation:** Query ratio of `LLM API calls` to `Agent Clicks on "Generate Reply"`.
- **Root Cause:** The ingestion pipeline may have been refactored to auto-trigger an AI draft for *every single incoming customer message*—including "Ok", "Thanks", "👍", or 3 rapid consecutive messages sent within 5 seconds—even if an agent never viewed or used the draft.

### Hypothesis 3: Model Routing Regression or Uncapped Retries
- **Investigation:** Group token costs by `model_name` and check error response rates.
- **Root Cause:** A release may have accidentally defaulted tier-1 queries to frontier reasoning models (e.g., Claude 3.5 Sonnet / GPT-4o at $3–$15/1M tokens) instead of cost-effective models (e.g., `gpt-4o-mini` or DeepInfra `Llama-3.1-8B` at $0.05–$0.15/1M tokens), or a bug in JSON validation caused silent 3x-retry loops on malformed outputs.

---

## 2. Concrete Remediation Plan

### 1. On-Demand & Debounced Generation
- Only invoke the LLM when an agent clicks **"Generate Reply"** (or after a 15-second debounce window on customer bursts).
- Implement a lightweight regex/heuristic filter to bypass LLM calls for simple conversational acknowledgments ("Thank you", "Got it", "Understood").

### 2. Tiered Model Routing via OpenRouter
- Route **85% of standard tier-1 inquiries** (order status, shipping timelines, basic returns) to lightweight models:
  - `openai/gpt-4o-mini` ($0.15 / 1M prompt tokens)
  - `deepinfra/meta-llama/llama-3.1-8b-instruct` ($0.05 / 1M prompt tokens)
- Reserve frontier models (Claude 3.5 Sonnet / GPT-4o) exclusively for complex multi-policy disputes or escalations flagged by policy guardrails.

### 3. Prompt Caching & Sliding Window Context
- **Enable Prompt Caching:** Place static system instructions and brand tone guidelines at the very prefix of the prompt so OpenRouter/Anthropic/OpenAI prompt caching delivers a **50% to 90% discount on repeated prompt tokens**.
- **Sliding History Window:** Restrict conversation context to the latest 6 turns plus a 1-sentence rolling summary of older messages.
- **Strict Retrieval Top-K:** Limit RAG context to the top 3 most relevant policy chunks rather than full document dumps.

### 4. Per-Brand Token Budgets & Semantic Caching
- Cache verified AI replies in Redis for identical high-frequency questions per brand (e.g. *"What is your return policy?"* or *"How long does delivery take?"*).
- Introduce hard per-brand daily token allowances and automated Slack anomaly alerts if any brand exceeds 2x their historical token run-rate.

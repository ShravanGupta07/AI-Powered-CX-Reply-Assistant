-- schema.sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. Brands Table
CREATE TABLE IF NOT EXISTS brands (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  tone TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Knowledge Base Table (Manageable per brand)
CREATE TABLE IF NOT EXISTS knowledge_base (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  brand_id UUID REFERENCES brands(id) ON DELETE CASCADE,
  category TEXT NOT NULL, -- 'Return Policy', 'Refund Policy', 'Shipping Policy', 'Cancellation Policy'
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Conversations & Order Context Table
CREATE TABLE IF NOT EXISTS conversations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  brand_id UUID REFERENCES brands(id) ON DELETE CASCADE,
  customer_name TEXT NOT NULL,
  order_id TEXT NOT NULL,
  product_name TEXT NOT NULL,
  order_status TEXT NOT NULL,
  days_since_delivery INT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Messages Table (Live Chat History)
CREATE TABLE IF NOT EXISTS messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  sender TEXT NOT NULL CHECK (sender IN ('customer', 'agent')),
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. AI Audit & Generation Logs Table (Requirement #5)
CREATE TABLE IF NOT EXISTS ai_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  customer_message TEXT NOT NULL,
  retrieved_context JSONB NOT NULL,
  ai_generated_response TEXT NOT NULL,
  agent_edited_response TEXT,
  final_response TEXT,
  guardrail_status TEXT NOT NULL, -- 'APPROVED_BY_POLICY', 'POLICY_RESTRICTION', 'MISSING_KB_INFO'
  reasoning TEXT,
  latency_ms INT,
  tokens_used INT,
  rag_status TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Disable Row Level Security hurdles for instant reviewer testing
ALTER TABLE brands DISABLE ROW LEVEL SECURITY;
ALTER TABLE knowledge_base DISABLE ROW LEVEL SECURITY;
ALTER TABLE conversations DISABLE ROW LEVEL SECURITY;
ALTER TABLE messages DISABLE ROW LEVEL SECURITY;
ALTER TABLE ai_logs DISABLE ROW LEVEL SECURITY;

-- Seed Brands
INSERT INTO brands (id, name, tone) VALUES
('11111111-1111-1111-1111-111111111111', 'Aura Botanics (Strict 7-Day Policy)', 'Warm, empathetic, polite, and strictly compliant with timelines'),
('22222222-2222-2222-2222-222222222222', 'Titan Gear Hydration (Flexible 30-Day Policy)', 'Energetic, rugged, customer-first, and reassuring')
ON CONFLICT (id) DO NOTHING;

-- Seed Brand A Knowledge Base (Aura Botanics - Strict 7 Days)
INSERT INTO knowledge_base (brand_id, category, title, content) VALUES
('11111111-1111-1111-1111-111111111111', 'Return Policy', 'Damaged or Broken Glass Bottles', 'If a glass serum or toner bottle arrives broken, customers must report it within 48 hours of delivery with a photo of the damaged bottle and box for a free replacement.'),
('11111111-1111-1111-1111-111111111111', 'Refund Policy', '7-Day Strict Refund Window', 'Refunds are strictly permitted only within 7 days of delivery. Any refund request made after 7 days of delivery is ineligible for a refund or replacement under any circumstances.'),
('11111111-1111-1111-1111-111111111111', 'Shipping Policy', 'Standard Dispatch & Delivery', 'Orders ship from our Mumbai warehouse within 24 hours and take 3-5 business days via BlueDart.'),
('11111111-1111-1111-1111-111111111111', 'Cancellation Policy', 'Pre-Dispatch Cancellation', 'Orders can only be cancelled within 4 hours of placement before the shipping label is generated.')
ON CONFLICT DO NOTHING;

-- Seed Brand B Knowledge Base (Titan Gear - Flexible 30 Days)
INSERT INTO knowledge_base (brand_id, category, title, content) VALUES
('22222222-2222-2222-2222-222222222222', 'Return Policy', '30-Day No-Questions-Asked Returns', 'Customers can return or exchange any bottle or gear within 30 days of delivery, including items damaged in transit—no photo proof required.'),
('22222222-2222-2222-2222-222222222222', 'Refund Policy', '30-Day Full Money-Back Guarantee', 'Full refunds to the original UPI or card payment method are permitted up to 30 days after delivery. Processed within 2 business days.'),
('22222222-2222-2222-2222-222222222222', 'Shipping Policy', 'Express Pan-India Shipping', 'Free express shipping on all orders above ₹999. Delivered within 2-3 business days.'),
('22222222-2222-2222-2222-222222222222', 'Cancellation Policy', 'Anytime Cancellation Before Delivery', 'Orders can be cancelled anytime prior to final delivery for a 100% instant refund.')
ON CONFLICT DO NOTHING;

-- Seed Conversations
INSERT INTO conversations (id, brand_id, customer_name, order_id, product_name, order_status, days_since_delivery) VALUES
('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'Ananya Sharma', 'ORD-AURA-9021', 'Vitamin C Glow Glass Bottle (50ml)', 'Delivered', 2),
('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-1111-1111-1111-111111111111', 'Rohan Verma', 'ORD-AURA-8410', 'Rosewater Toning Mist Bottle', 'Delivered', 20),
('cccccccc-cccc-cccc-cccc-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'Vikram Nair', 'ORD-TITAN-3319', 'Titan Insulated Flask 1L', 'Delivered', 20)
ON CONFLICT (id) DO NOTHING;

-- Seed Initial Messages (Testing Happy Path + Guardrail Scenarios)
INSERT INTO messages (conversation_id, sender, content) VALUES
('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'customer', 'My order was delivered but the bottle is broken. What can I do?'),
('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'customer', 'I received this 20 days ago. Can I get a refund?'),
('cccccccc-cccc-cccc-cccc-cccccccccccc', 'customer', 'I received this 20 days ago and the bottle cap is cracked. Can I get a refund?')
ON CONFLICT DO NOTHING;

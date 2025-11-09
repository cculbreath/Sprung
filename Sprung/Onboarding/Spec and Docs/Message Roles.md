Understanding previous_response_id, instructions, and Developer Messages in the OpenAI Responses API

This document summarizes how conversation context works when using the OpenAI Responses API, especially when chaining requests with previous_response_id. It’s intended as a quick design reference for LLM coding agents and developers.

⸻

1. Conversation Chaining via previous_response_id

The previous_response_id parameter allows you to continue a conversation from a prior response without manually resending the full history.

When you include:

"previous_response_id": "resp_abc123xyz"

the model implicitly loads all prior messages (user, assistant, system/developer) that led up to that response. This preserves conversational state and continuity.

However, not all context types persist equally.

⸻

2. The Three Main Context Types

Context Source	Persists Across Turns	Overrides Others When Present	Notes
developer / system role messages in input	✅ Yes	⚠️ Can be overridden temporarily by instructions	Added once to the conversation and stored automatically.
instructions parameter	❌ No	✅ Highest precedence for that turn only	Must be re-sent each turn if you want persistence.
user / assistant messages	✅ Yes	N/A	Always carried over via previous_response_id.


⸻

3. How instructions Works

Behavior
	•	Injects a one-off system/developer message into the model’s context for that specific request only.
	•	Does not persist when chaining with previous_response_id.
	•	When omitted, no instructions are inherited from previous calls.

Example

Turn 1:

{
  "model": "gpt-4o",
  "instructions": "Always talk like a pirate.",
  "input": [ { "role": "user", "content": [{ "type": "input_text", "text": "hello" }] } ],
  "store": true
}

→ Response: “Arrrrr there!” → returns id: resp_abc123

Turn 2:

{
  "model": "gpt-4o",
  "previous_response_id": "resp_abc123",
  "input": [ { "role": "user", "content": [{ "type": "input_text", "text": "nice weather today" }] } ]
}

→ Response: Normal tone (no pirate speak). The instructions field from turn 1 is not reused.

Turn 3 (Override):

{
  "model": "gpt-4o",
  "instructions": "Decorum is critical. Drop the pirate schtick.",
  "previous_response_id": "resp_abc123",
  "input": [ { "role": "user", "content": [{ "type": "input_text", "text": "nice weather today" }] } ]
}

→ Response: “Indeed, quite pleasant weather today.”

⸻

4. How developer Role Messages Work

Messages with role developer (or system) placed inside input become part of the persistent conversation history and therefore do persist across chained responses.

Example

Turn 1:

{
  "model": "gpt-4o",
  "input": [
    { "role": "developer", "content": [{ "type": "input_text", "text": "Always talk like a pirate." }] },
    { "role": "user", "content": [{ "type": "input_text", "text": "hello" }] }
  ],
  "store": true
}

→ Response: “Rrrrr there, matey!” → returns id: resp_abc123

Turn 2:

{
  "model": "gpt-4o",
  "previous_response_id": "resp_abc123",
  "input": [ { "role": "user", "content": [{ "type": "input_text", "text": "nice weather today" }] } ]
}

→ Response: “Aye, fair winds today!” (still pirate style)

Overriding Temporarily with instructions

You can override a developer message for a single turn using instructions:

{
  "model": "gpt-4o",
  "instructions": "Speak formally. Drop the pirate tone.",
  "previous_response_id": "resp_abc123",
  "input": [ { "role": "user", "content": [{ "type": "input_text", "text": "nice weather today" }] } ]
}

→ The model will speak formally for this call only.

If you omit instructions on the next turn, the model reverts to the persistent developer message (pirate tone).

⸻

5. Override Hierarchy Summary

User / Assistant messages   →  Always persist.
Developer message in input  →  Persistent baseline behavior.
Instructions parameter      →  Temporary override for this call.

Precedence for a single request

instructions ⟶ developer ⟶ user/assistant

Persistence across requests

developer ⟶ user/assistant ⟶ instructions (non-persistent)

⸻

6. Practical Design Recommendations for LLM Agents

Goal	Recommended Approach
Persistent behavior or personality	Use a developer role message in input on the first request.
Temporary behavior change	Use instructions for a one-off modification.
Replace previous personality permanently	Send a new developer role message that updates or contradicts the old one.
Dynamic system prompt each turn	Always include the desired instructions explicitly on every call.


⸻

7. Example Conversation Timeline (Mixed Usage)

Turn 1 – Establish baseline (developer message persists):

{
  "model": "gpt-4o",
  "input": [
    { "role": "developer", "content": [{ "type": "input_text", "text": "Always talk like a pirate." }] },
    { "role": "user", "content": [{ "type": "input_text", "text": "hello" }] }
  ],
  "store": true
}

→ “Rrrrr!”

Turn 2 – Temporary override with instructions:

{
  "model": "gpt-4o",
  "instructions": "Decorum is critical, drop the pirate schtick.",
  "previous_response_id": "resp_abc123",
  "input": [ { "role": "user", "content": [{ "type": "input_text", "text": "nice weather today" }] } ]
}

→ “Indeed, pleasant weather.”

Turn 3 – No instructions, so revert to developer context:

{
  "model": "gpt-4o",
  "previous_response_id": "resp_def456",
  "input": [ { "role": "user", "content": [{ "type": "input_text", "text": "What deck is this?" }] } ]
}

→ “Rrrrr, it’s the poop deck, matey!”

⸻

8. Key Takeaways
	•	previous_response_id carries conversation history but not instructions.
	•	instructions is a one-shot system message.
	•	Developer messages in input are persistent.
	•	instructions has highest precedence for its request only.
	•	If you need stateful persona or rules, use developer messages.

⸻

Example Decision Flow for Agents
	1.	Do I want this instruction to persist?  → If yes, make it a developer message.
	2.	Do I only want to override behavior for one request?  → Use instructions.
	3.	Am I continuing the same session?  → Include previous_response_id and omit repeated messages.

⸻

Quick Reference

Parameter	Scope	Persistence	Typical Use
previous_response_id	Context chaining	✅	Continue conversation without resending history
instructions	Ephemeral	❌	One-off style or behavior override
developer message	Conversation baseline	✅	Persistent persona, policy, or behavior
user message	Conversation content	✅	Normal turn-based interaction


⸻

Author: Internal design guide for LLM agent developers
Use case: Teaching coding agents how to maintain, override, or reset behavior in OpenAI’s Responses API
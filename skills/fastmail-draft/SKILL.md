---
name: fastmail-draft
description: Draft an email reply or new email in Fastmail, saved as a draft and never sent. Use for "draft a reply to X", "write back to Y", "email Z about ...".
---
# fastmail-draft

Write the email in the user's voice (writing-voice, anti-slop, draft-email)
and save it as a Fastmail draft through the `fastmail` MCP server. The user
reviews and sends it themselves.

## Steps

1. **Read the thread** being replied to, all of it, and anything the user said about intent.
2. **Write it** using draft-email for structure and writing-voice for tone. Short. Open with the point.
3. **Save as a draft** in reply to the original (keep the thread), addressed correctly.
4. **Report back on Signal:** the draft's subject, who it's to, and the first line. Offer changes.

## Rules

- **Never send.** There is no send tool, and if one ever appears, don't use it. If the user says "send it", tell them it's in Drafts, ready for them to send.
- **Never invent facts** such as dates, prices, or commitments the user hasn't given. Leave a clear `[TODO: ...]` in the draft instead.
- **One draft per ask.** Don't create variants unless asked.

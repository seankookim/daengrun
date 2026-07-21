# Product notes

## Decisions made

- **One app, role toggle at signup** (switch anytime later; many runners are also owners)
- **Korean-first** UI, Kakao login/pay conventions
- **MVP core**: request → match → live GPS run → payment → review
- **Matching = hybrid**: app computes a strong in-house recommendation by matching both sides' preferences (location, route type, pace, dog size/breed, schedule — like hospital residency matching). Both parties still see a ranked list of alternatives and can choose manually. The recommendation is made visually dominant.
- **Bodycam live feed**: runners get a small strap-on bodycam (police-style). Owners can watch the run live. This + GPS is the core trust differentiator.
- **Premium add-ons** (paid per-run by owner): river-view course, dirt-only paths, snack breaks, dog meetups with nearby runners
- **Community tab**: shared feed for owners + runners — run records, streaks, mileage, dog photos, snack purchases, mini tweets
- **Shop**: co-branded pet products (leashes, snacks, premium food, apparel, dog-a-mins, toys)

## Open questions

- Commission rate (20% placeholder in prototype) — decide later
- Pickup handoff verification: QR scan? photo confirmation? This is where liability lives.
- Bodycam: hardware cost, who owns it, privacy law (filming in public in Korea), streaming infra cost
- Premium runner tier definition (훈련사 certification? higher verification level?)
- Multi-dog group runs: member-only, lower price — post-MVP
- 맹견/입마개 regulation compliance; animal protection law liability; insurance partner

## Roadmap (rough)

1. Prototype iteration (now)
2. Competitor/pricing research (도그메이트, 우프, 페오펫 etc.)
3. Pick real stack (likely React Native + Supabase/Firebase for MVP)
4. Pilot: one Seoul district, hand-recruited runners

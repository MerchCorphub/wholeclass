# WholeClass™ — The Know Your Holes Discovery Class

**Become Your Discovery.** · https://wholeclass.app

A home-screen web app (PWA) for the 14-Day Discovery Class, inspired by *Know Your Holes* by C.P. Parker. Owned and operated by Merch Corporation.

## How it is built

| Part | Where |
|---|---|
| App pages | `index.html` (the whole app), `terms.html`, `privacy.html` — served by GitHub Pages at wholeclass.app |
| Database & sign-in | Supabase project **wholeclass** (`uiwbwiznuradpmfdeeuy`), schema in `supabase/migrations/` |
| Payments | Stripe Checkout through the `stripe-pay` server function (`supabase/functions/stripe-pay/`) |
| Price | `public.prices` table — $20, one year, no automatic renewal |

## Ways to open Days 2–14

- **Buy** — $20 for one year (Stripe).
- **Book key** — printed in the book; add keys with SQL: `insert into public.book_keys (code, batch) values ('ABCD-1234', 'first printing');`
- **Guided group** — create a group with SQL: `insert into public.groups (name, code, seats) values ('Grace Church', 'GRACE24', 50);` Facilitators see completion only, never answers.
- **Gifted seat** — members who bought or used a book key can give 4 seats a year (30 days each) from More › Challenge someone.

## Privacy

Every table uses row-level security: members can read and write only their own rows. Access and payments change only through database functions.

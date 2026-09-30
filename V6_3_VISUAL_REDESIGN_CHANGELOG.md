# Pharmacy Abdelhadi V6.3.0 — Visual Redesign

## Purpose
A full visual redesign based on the approved Pharmacy Abdelhadi reference concept: light, spacious, green/ivory/gold, modern RTL SaaS/pharmacy workspace.

## Scope
Visual/UI layer only. Existing React components, Supabase RPC calls, database logic, workflows, fields and information are preserved.

## Areas redesigned
- Administration shell / sidebar / topbar
- Dashboard and KPI cards
- POS workbench and invoice
- Purchases and purchase invoice
- Reports and analytical panels
- Tables, forms, cards, modals and status states
- Customer storefront / header / hero / products / offers
- Login screen
- Responsive/mobile layouts

## Safety
- No SQL changes.
- No RPC names changed.
- No existing data model changes.
- `REDESIGN_V6_3.css` is a dedicated visual override layer loaded after the existing stylesheet.

## Validation
- JSX/TS transpilation check: PASS
- CSS brace balance: PASS
- Existing RPC call inventory compared before/after: expected unchanged
- SQL files untouched
- Production browser/Vercel E2E build must still be run in the deployment environment because dependency installation/build is not guaranteed in this workspace.

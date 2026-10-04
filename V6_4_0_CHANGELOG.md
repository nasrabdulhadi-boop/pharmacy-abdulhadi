# Pharmacy Abdelhadi V6.4.0

- Purchase bonus/free units are recorded separately from paid quantity.
- Invoice total, supplier debt, payment and product purchase price use paid quantity only.
- Bonus units enter stock through a zero-cost bonus batch and are fully sellable.
- POS allows changing the net unit price for the current sale line only. Product, batch, purchase and inventory prices are not updated by the POS override.
- Sale items preserve base_unit_price for audit/traceability; reports and returns continue using the actual unit_price sold.
- Dashboard day details and reports expose bonus quantities without changing financial totals.
- Supplier returns include bonus batches at zero value.
- Dashboard day-details panel is widened only; its data/sections/behavior are unchanged.

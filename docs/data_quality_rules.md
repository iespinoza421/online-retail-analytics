# Data Quality Rules

## Purpose

This document defines the classification and treatment rules applied to
the Online Retail transaction dataset.

The raw source is immutable. No source row is silently deleted. Every row
must remain traceable through `SourceRowNumber` and receive a transaction
classification.

## Dataset Grain

The source represents transaction lines. However, it does not include a
unique invoice-line identifier.

Repeated combinations of invoice, product, quantity, date, price,
customer, country, and source period cannot be conclusively classified
as technical duplicates.

## Transaction Classification Rules

### SALE

Condition:

- `Quantity > 0`
- `UnitPrice > 0`
- Invoice does not begin with `C`

Treatment:

- Include in the commercial sales model.

### CANCELLATION

Condition:

- Invoice begins with `C`
- `Quantity < 0`

Treatment:

- Include as a negative commercial transaction.
- Preserve its negative quantity and revenue.

### FREE_ITEM

Condition:

- `Quantity > 0`
- `UnitPrice == 0`
- `CustomerID` is present

Treatment:

- Retain as a commercial transaction with zero revenue.
- Identify separately from paid sales.

### INVENTORY_ADJUSTMENT

Condition:

- `UnitPrice == 0`
- `CustomerID` is missing
- Record does not meet the cancellation rule

Treatment:

- Exclude from commercial revenue calculations.
- Preserve in the adjustment output.

Observed descriptions include:

- damaged
- damages
- wet
- check
- test
- Found
- dotcom
- amazon
- samples/damages

### FINANCIAL_ADJUSTMENT

Condition:

- `UnitPrice < 0`
- Or description identifies a financial correction such as
  `Adjust bad debt`

Treatment:

- Exclude from product-sales calculations.
- Preserve in the financial-adjustment output.

### UNKNOWN

Condition:

- Record does not match any documented rule.

Treatment:

- Send to manual review.
- Do not silently discard.

## Missing Customer IDs

A missing `CustomerID` does not automatically invalidate a paid sale.

Treatment:

- Retain paid transactions without a customer in total sales analysis.
- Exclude them only from customer-level analysis such as segmentation,
  retention, and customer lifetime value.

## Missing Descriptions

Missing descriptions are evaluated together with quantity, price, and
customer information.

Observed missing descriptions are associated with non-commercial
inventory adjustments.

Treatment:

- Do not impute a product description without evidence.
- Preserve the original missing value.
- Use the transaction classification to determine analytical inclusion.

## Exact Duplicate Candidates

The initial profile found:

- 469 rows belonging to repeated groups
- 228 unique repeated combinations
- 241 additional appearances after the first
- Maximum group size of 5

Repeated rows occur within otherwise valid invoices and are interspersed
with other products. The same product may also appear multiple times with
different quantities.

Because the source has no unique invoice-line identifier, there is
insufficient evidence to determine that the repeated rows are extraction
errors.

Treatment:

- Do not remove exact duplicate candidates.
- Add `IsExactDuplicateCandidate` for transparency.
- Preserve `SourceRowNumber`.
- Aggregate quantities at the invoice-product-price level when producing
  summarized analytical tables.

## Reconciliation Requirement

Every source row must receive exactly one classification.

The pipeline must satisfy:

Source rows =
SALE +
CANCELLATION +
FREE_ITEM +
INVENTORY_ADJUSTMENT +
FINANCIAL_ADJUSTMENT +
UNKNOWN

The reconciliation count must equal 16,729 rows unless the source file
changes.

## Raw Data Protection

The workbook in `data/raw` must never be modified by transformation
scripts.

All derived outputs must be written to `data/processed` or
`data/rejected`.
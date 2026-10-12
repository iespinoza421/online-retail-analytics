# Initial Analytical Findings

## Revenue Overview

The commercial dataset contains:

- Gross sales: 336,438.69
- Total cancellation value: 254,700.13
- Observed net revenue: 81,738.56
- Adjusted net revenue: 327,391.76

Observed net revenue is calculated from every commercial transaction
available in the source.

Adjusted net revenue separates two exceptional cancellation records whose
corresponding sales are not present in the available dataset.

## Exceptional Cancellations

Two cancellation lines materially distort the aggregate results:

| Invoice | Customer | Stock Code | Units | Cancellation Value |
|---|---:|---|---:|---:|
| C541433 | 12346 | 23166 | 74,215 | 77,183.60 |
| C581484 | 16446 | 23843 | 80,995 | 168,469.60 |

Combined value:

- 245,653.20
- 96.45% of all cancellation value

The next-largest cancellation contains only 186 units. This large
separation supports treating the two records as exceptional transactions.

## Matching-Sale Investigation

The warehouse was searched for positive sales with the same:

- Customer
- Product
- Unit price
- Opposite quantity
- Earlier or equal transaction date

No matching sales were found.

This does not prove that the cancellations are erroneous. It demonstrates
that the available source does not contain the transactions required to
reconcile them.

The dataset includes only 925 unique invoices and should not be assumed to
represent the retailer's complete transaction history.

## Analytical Treatment

The records are not deleted or reclassified.

They remain included in:

- Source data
- Classified transactions
- Staging
- FactSales
- Observed net revenue

An additional analytical flag identifies cancellation lines with an
absolute quantity of at least 10,000 units.

This produces two measures:

### Observed Net Revenue

Includes every sale, free item, and cancellation in the source.

Observed net revenue:

81,738.56

### Adjusted Net Revenue

Excludes only the two exceptional, unmatched cancellation lines from the
operational measure.

Adjusted net revenue:

327,391.76

This adjusted measure is intended for operational trend analysis. It is
not presented as audited accounting revenue.

## Operational Cancellation Value

After separating the two exceptional records, the remaining cancellation
value is:

9,046.93

The operational cancellation rate is approximately:

2.69% of gross sales

## Reporting Recommendation

Dashboards should display:

1. Gross sales
2. Observed net revenue
3. Adjusted net revenue
4. Operational cancellation amount
5. Exceptional cancellation amount
6. A visible data-coverage note

This preserves transparency while preventing two unmatched records from
obscuring the broader operating pattern.
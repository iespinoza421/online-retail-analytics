import logging
from pathlib import Path

import pandas as pd


PROJECT_ROOT = Path(__file__).resolve().parents[1]

SOURCE_FILE = (
    PROJECT_ROOT
    / "data"
    / "raw"
    / "online_retail_transactions_raw.xlsx"
)

OUTPUT_DIRECTORY = (
    PROJECT_ROOT
    / "data"
    / "processed"
    / "quality_review"
)

EXPECTED_COLUMNS = [
    "Invoice",
    "StockCode",
    "Description",
    "Quantity",
    "InvoiceDate",
    "UnitPrice",
    "CustomerID",
    "Country",
    "SourcePeriod",
]

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
)

logger = logging.getLogger(__name__)


def load_source_data() -> pd.DataFrame:
    """Load the immutable transaction source."""

    if not SOURCE_FILE.exists():
        raise FileNotFoundError(
            f"Source file was not found: {SOURCE_FILE}"
        )

    dataframe = pd.read_excel(
        SOURCE_FILE,
        sheet_name="transactions_raw",
        dtype={
            "Invoice": "string",
            "StockCode": "string",
            "CustomerID": "string",
        },
    )

    actual_columns = dataframe.columns.tolist()

    if actual_columns != EXPECTED_COLUMNS:
        raise ValueError(
            "Unexpected source schema.\n"
            f"Expected: {EXPECTED_COLUMNS}\n"
            f"Actual:   {actual_columns}"
        )

    # Preserve the original Excel row for traceability.
    dataframe.insert(
        0,
        "SourceRowNumber",
        dataframe.index + 2,
    )

    return dataframe


def export_issue(
    dataframe: pd.DataFrame,
    mask: pd.Series,
    file_name: str,
) -> int:
    """Export matching records and return the number found."""

    issue_rows = dataframe.loc[mask].copy()
    output_file = OUTPUT_DIRECTORY / file_name

    issue_rows.to_csv(
        output_file,
        index=False,
        encoding="utf-8-sig",
    )

    logger.info(
        "%s: %s records",
        file_name,
        len(issue_rows),
    )

    return len(issue_rows)


def main() -> None:
    logger.info("Starting data-quality investigation")

    OUTPUT_DIRECTORY.mkdir(
        parents=True,
        exist_ok=True,
    )

    dataframe = load_source_data()

    invoice = dataframe["Invoice"].astype("string")
    cancelled_invoice = invoice.str.startswith("C", na=False)
    negative_quantity = dataframe["Quantity"] < 0
    nonpositive_price = dataframe["UnitPrice"] <= 0

    comparison_columns = [
        column
        for column in dataframe.columns
        if column != "SourceRowNumber"
    ]

    exact_duplicate = dataframe.duplicated(
        subset=comparison_columns,
        keep=False,
    )

    issues = {
        "exact_duplicates": export_issue(
            dataframe,
            exact_duplicate,
            "exact_duplicates.csv",
        ),
        "cancelled_invoices": export_issue(
            dataframe,
            cancelled_invoice,
            "cancelled_invoices.csv",
        ),
        "negative_quantities": export_issue(
            dataframe,
            negative_quantity,
            "negative_quantities.csv",
        ),
        "negative_without_cancellation": export_issue(
            dataframe,
            negative_quantity & ~cancelled_invoice,
            "negative_without_cancellation.csv",
        ),
        "missing_customer_ids": export_issue(
            dataframe,
            dataframe["CustomerID"].isna(),
            "missing_customer_ids.csv",
        ),
        "missing_descriptions": export_issue(
            dataframe,
            dataframe["Description"].isna(),
            "missing_descriptions.csv",
        ),
        "nonpositive_prices": export_issue(
            dataframe,
            nonpositive_price,
            "nonpositive_prices.csv",
        ),
    }

    summary = pd.DataFrame(
        [
            {
                "issue": issue,
                "row_count": count,
                "percentage_of_source": round(
                    count / len(dataframe) * 100,
                    4,
                ),
            }
            for issue, count in issues.items()
        ]
    )

    summary.to_csv(
        OUTPUT_DIRECTORY / "quality_issue_summary.csv",
        index=False,
        encoding="utf-8-sig",
    )

    logger.info(
        "Quality review saved to: %s",
        OUTPUT_DIRECTORY,
    )
    logger.info("Investigation completed successfully")


if __name__ == "__main__":
    main()
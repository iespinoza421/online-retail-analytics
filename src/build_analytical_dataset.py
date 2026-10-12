import json
import logging
from pathlib import Path

import pandas as pd


PROJECT_ROOT = Path(__file__).resolve().parents[1]

INPUT_FILE = (
    PROJECT_ROOT
    / "data"
    / "processed"
    / "commercial_transactions.csv"
)

OUTPUT_DIRECTORY = PROJECT_ROOT / "data" / "processed"

ANALYTICAL_FILE = (
    OUTPUT_DIRECTORY / "invoice_product_summary.csv"
)

SUMMARY_FILE = (
    OUTPUT_DIRECTORY / "analytical_dataset_summary.json"
)

GROUPING_COLUMNS = [
    "Invoice",
    "StockCode",
    "Description",
    "InvoiceDate",
    "UnitPrice",
    "CustomerID",
    "Country",
    "SourcePeriod",
    "TransactionType",
]

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
)

logger = logging.getLogger(__name__)


def load_commercial_transactions() -> pd.DataFrame:
    """Load the classified commercial transaction lines."""

    if not INPUT_FILE.exists():
        raise FileNotFoundError(
            "Commercial transaction file was not found. "
            "Run transform_transactions.py first."
        )

    dataframe = pd.read_csv(
        INPUT_FILE,
        dtype={
            "Invoice": "string",
            "StockCode": "string",
            "CustomerID": "string",
        },
        parse_dates=["InvoiceDate"],
    )

    required_columns = {
        "SourceRowNumber",
        "Quantity",
        "LineAmount",
        "IsExactDuplicateCandidate",
        *GROUPING_COLUMNS,
    }

    missing_columns = required_columns.difference(
        dataframe.columns
    )

    if missing_columns:
        raise ValueError(
            "Commercial transaction file is missing columns: "
            f"{sorted(missing_columns)}"
        )

    return dataframe


def build_invoice_product_summary(
    dataframe: pd.DataFrame,
) -> pd.DataFrame:
    """Aggregate lines at invoice-product-price grain."""

    grouped = (
        dataframe.groupby(
            GROUPING_COLUMNS,
            dropna=False,
            sort=False,
        )
        .agg(
            Quantity=(
                "Quantity",
                "sum",
            ),
            LineAmount=(
                "LineAmount",
                "sum",
            ),
            SourceLineCount=(
                "SourceRowNumber",
                "count",
            ),
            DuplicateCandidateLineCount=(
                "IsExactDuplicateCandidate",
                "sum",
            ),
            FirstSourceRowNumber=(
                "SourceRowNumber",
                "min",
            ),
            SourceRowNumbers=(
                "SourceRowNumber",
                lambda values: ",".join(
                    str(int(value))
                    for value in sorted(values)
                ),
            ),
        )
        .reset_index()
    )

    grouped["LineAmount"] = (
        grouped["LineAmount"].round(2)
    )

    grouped["DuplicateCandidateLineCount"] = (
        grouped["DuplicateCandidateLineCount"].astype(int)
    )

    grouped.insert(
        0,
        "AnalyticalLineID",
        range(1, len(grouped) + 1),
    )

    grouped["HasMultipleSourceLines"] = (
        grouped["SourceLineCount"] > 1
    )

    return grouped


def validate_aggregation(
    source: pd.DataFrame,
    analytical: pd.DataFrame,
) -> None:
    """Validate quantities, amounts, and source lineage."""

    source_quantity = float(
        source["Quantity"].sum()
    )

    analytical_quantity = float(
        analytical["Quantity"].sum()
    )

    if source_quantity != analytical_quantity:
        raise ValueError(
            "Quantity reconciliation failed: "
            f"{source_quantity} != {analytical_quantity}"
        )

    source_amount = round(
        float(source["LineAmount"].sum()),
        2,
    )

    analytical_amount = round(
        float(analytical["LineAmount"].sum()),
        2,
    )

    if source_amount != analytical_amount:
        raise ValueError(
            "Revenue reconciliation failed: "
            f"{source_amount} != {analytical_amount}"
        )

    reconstructed_lines = int(
        analytical["SourceLineCount"].sum()
    )

    if reconstructed_lines != len(source):
        raise ValueError(
            "Lineage reconciliation failed: "
            f"{reconstructed_lines} != {len(source)}"
        )

    if analytical["AnalyticalLineID"].duplicated().any():
        raise ValueError(
            "AnalyticalLineID contains duplicate values."
        )

    if analytical["AnalyticalLineID"].isna().any():
        raise ValueError(
            "AnalyticalLineID contains missing values."
        )


def save_outputs(
    source: pd.DataFrame,
    analytical: pd.DataFrame,
) -> dict:
    """Save the analytical dataset and its summary."""

    OUTPUT_DIRECTORY.mkdir(
        parents=True,
        exist_ok=True,
    )

    analytical.to_csv(
        ANALYTICAL_FILE,
        index=False,
        encoding="utf-8-sig",
    )

    summary = {
        "source_commercial_rows": int(len(source)),
        "analytical_rows": int(len(analytical)),
        "rows_consolidated": int(
            len(source) - len(analytical)
        ),
        "source_quantity": float(
            source["Quantity"].sum()
        ),
        "analytical_quantity": float(
            analytical["Quantity"].sum()
        ),
        "source_line_amount": round(
            float(source["LineAmount"].sum()),
            2,
        ),
        "analytical_line_amount": round(
            float(analytical["LineAmount"].sum()),
            2,
        ),
        "multi_source_line_groups": int(
            analytical["HasMultipleSourceLines"].sum()
        ),
        "duplicate_candidate_lines": int(
            analytical[
                "DuplicateCandidateLineCount"
            ].sum()
        ),
        "reconciliation_passed": True,
    }

    with SUMMARY_FILE.open(
        "w",
        encoding="utf-8",
    ) as file:
        json.dump(
            summary,
            file,
            indent=4,
            ensure_ascii=False,
        )

    return summary


def main() -> None:
    """Build and validate the analytical dataset."""

    logger.info("Starting analytical dataset build")

    source = load_commercial_transactions()

    analytical = build_invoice_product_summary(
        source
    )

    validate_aggregation(
        source,
        analytical,
    )

    summary = save_outputs(
        source,
        analytical,
    )

    logger.info(
        "Commercial source rows: %s",
        summary["source_commercial_rows"],
    )

    logger.info(
        "Analytical rows: %s",
        summary["analytical_rows"],
    )

    logger.info(
        "Rows consolidated: %s",
        summary["rows_consolidated"],
    )

    logger.info(
        "Commercial amount: %s",
        summary["analytical_line_amount"],
    )

    logger.info(
        "Duplicate-candidate lines: %s",
        summary["duplicate_candidate_lines"],
    )

    logger.info(
        "Reconciliation passed: %s",
        summary["reconciliation_passed"],
    )

    logger.info(
        "Analytical dataset completed successfully"
    )


if __name__ == "__main__":
    main()
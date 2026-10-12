import json
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

PROCESSED_DIRECTORY = PROJECT_ROOT / "data" / "processed"
REJECTED_DIRECTORY = PROJECT_ROOT / "data" / "rejected"

TRANSFORMED_FILE = (
    PROCESSED_DIRECTORY / "transactions_classified.csv"
)
COMMERCIAL_FILE = (
    PROCESSED_DIRECTORY / "commercial_transactions.csv"
)
ADJUSTMENTS_FILE = (
    PROCESSED_DIRECTORY / "adjustments.csv"
)
SUMMARY_FILE = (
    PROCESSED_DIRECTORY / "transformation_summary.json"
)
REJECTED_FILE = (
    REJECTED_DIRECTORY / "unknown_transactions.csv"
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

DUPLICATE_COMPARISON_COLUMNS = EXPECTED_COLUMNS.copy()

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
)

logger = logging.getLogger(__name__)


def load_source_data() -> pd.DataFrame:
    """Load and validate the immutable source workbook."""

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

    dataframe.insert(
        0,
        "SourceRowNumber",
        dataframe.index + 2,
    )

    return dataframe


def add_duplicate_indicator(
    dataframe: pd.DataFrame,
) -> pd.DataFrame:
    """Flag all rows that belong to an exact repeated group."""

    result = dataframe.copy()

    result["IsExactDuplicateCandidate"] = result.duplicated(
        subset=DUPLICATE_COMPARISON_COLUMNS,
        keep=False,
    )

    return result


def classify_transactions(
    dataframe: pd.DataFrame,
) -> pd.DataFrame:
    """Classify every source row using documented rules."""

    result = dataframe.copy()

    invoice = result["Invoice"].astype("string")
    description = result["Description"].astype("string")

    cancellation = (
        invoice.str.startswith("C", na=False)
        & (result["Quantity"] < 0)
    )

    financial_adjustment = (
        (result["UnitPrice"] < 0)
        | description.str.contains(
            "bad debt",
            case=False,
            na=False,
        )
    )

    free_item = (
        (result["Quantity"] > 0)
        & (result["UnitPrice"] == 0)
        & result["CustomerID"].notna()
    )

    inventory_adjustment = (
        (result["UnitPrice"] == 0)
        & result["CustomerID"].isna()
        & ~cancellation
        & ~financial_adjustment
    )

    sale = (
        (result["Quantity"] > 0)
        & (result["UnitPrice"] > 0)
        & ~invoice.str.startswith("C", na=False)
    )

    result["TransactionType"] = "UNKNOWN"
    result["ClassificationReason"] = (
        "Record does not match a documented rule"
    )

    result.loc[
        sale,
        ["TransactionType", "ClassificationReason"],
    ] = [
        "SALE",
        "Positive quantity and positive unit price",
    ]

    result.loc[
        cancellation,
        ["TransactionType", "ClassificationReason"],
    ] = [
        "CANCELLATION",
        "Invoice begins with C and quantity is negative",
    ]

    result.loc[
        free_item,
        ["TransactionType", "ClassificationReason"],
    ] = [
        "FREE_ITEM",
        "Positive quantity, zero price, and identified customer",
    ]

    result.loc[
        inventory_adjustment,
        ["TransactionType", "ClassificationReason"],
    ] = [
        "INVENTORY_ADJUSTMENT",
        "Zero price and missing customer",
    ]

    result.loc[
        financial_adjustment,
        ["TransactionType", "ClassificationReason"],
    ] = [
        "FINANCIAL_ADJUSTMENT",
        "Negative price or bad-debt description",
    ]

    result["LineAmount"] = (
        result["Quantity"] * result["UnitPrice"]
    ).round(2)

    result["IsCommercialTransaction"] = (
        result["TransactionType"].isin(
            ["SALE", "CANCELLATION", "FREE_ITEM"]
        )
    )

    return result


def validate_transformation(
    source: pd.DataFrame,
    transformed: pd.DataFrame,
) -> None:
    """Ensure that transformation preserves and classifies every row."""

    if len(source) != len(transformed):
        raise ValueError(
            "Reconciliation failed: source and transformed "
            "row counts are different."
        )

    if transformed["TransactionType"].isna().any():
        raise ValueError(
            "Transformation failed: some rows have no classification."
        )

    if transformed["SourceRowNumber"].duplicated().any():
        raise ValueError(
            "Transformation failed: SourceRowNumber is not unique."
        )

    expected_source_rows = set(source["SourceRowNumber"])
    actual_source_rows = set(transformed["SourceRowNumber"])

    if expected_source_rows != actual_source_rows:
        raise ValueError(
            "Transformation failed: source-row traceability "
            "was not preserved."
        )


def save_outputs(dataframe: pd.DataFrame) -> dict:
    """Save classified datasets and return summary statistics."""

    PROCESSED_DIRECTORY.mkdir(
        parents=True,
        exist_ok=True,
    )
    REJECTED_DIRECTORY.mkdir(
        parents=True,
        exist_ok=True,
    )

    commercial = dataframe.loc[
        dataframe["IsCommercialTransaction"]
    ].copy()

    adjustments = dataframe.loc[
        dataframe["TransactionType"].isin(
            [
                "INVENTORY_ADJUSTMENT",
                "FINANCIAL_ADJUSTMENT",
            ]
        )
    ].copy()

    unknown = dataframe.loc[
        dataframe["TransactionType"] == "UNKNOWN"
    ].copy()

    dataframe.to_csv(
        TRANSFORMED_FILE,
        index=False,
        encoding="utf-8-sig",
    )

    commercial.to_csv(
        COMMERCIAL_FILE,
        index=False,
        encoding="utf-8-sig",
    )

    adjustments.to_csv(
        ADJUSTMENTS_FILE,
        index=False,
        encoding="utf-8-sig",
    )

    unknown.to_csv(
        REJECTED_FILE,
        index=False,
        encoding="utf-8-sig",
    )

    classification_counts = (
        dataframe["TransactionType"]
        .value_counts(dropna=False)
        .to_dict()
    )

    classification_counts = {
        str(classification): int(count)
        for classification, count
        in classification_counts.items()
    }

    summary = {
        "source_rows": int(len(dataframe)),
        "classified_rows": int(
            sum(classification_counts.values())
        ),
        "reconciliation_passed": (
            len(dataframe)
            == sum(classification_counts.values())
        ),
        "classification_counts": classification_counts,
        "commercial_rows": int(len(commercial)),
        "adjustment_rows": int(len(adjustments)),
        "unknown_rows": int(len(unknown)),
        "exact_duplicate_candidate_rows": int(
            dataframe["IsExactDuplicateCandidate"].sum()
        ),
        "total_line_amount": round(
            float(dataframe["LineAmount"].sum()),
            2,
        ),
        "commercial_line_amount": round(
            float(commercial["LineAmount"].sum()),
            2,
        ),
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
    logger.info("Starting transaction transformation")

    source = load_source_data()
    transformed = add_duplicate_indicator(source)
    transformed = classify_transactions(transformed)

    validate_transformation(source, transformed)
    summary = save_outputs(transformed)

    logger.info("Source rows: %s", summary["source_rows"])
    logger.info(
        "Classification counts: %s",
        summary["classification_counts"],
    )
    logger.info(
        "Duplicate-candidate rows: %s",
        summary["exact_duplicate_candidate_rows"],
    )
    logger.info(
        "Unknown rows: %s",
        summary["unknown_rows"],
    )
    logger.info(
        "Reconciliation passed: %s",
        summary["reconciliation_passed"],
    )
    logger.info("Transformation completed successfully")


if __name__ == "__main__":
    main()
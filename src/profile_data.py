import hashlib
import json
import logging
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd


PROJECT_ROOT = Path(__file__).resolve().parents[1]

SOURCE_FILE = (
    PROJECT_ROOT
    / "data"
    / "raw"
    / "online_retail_transactions_raw.xlsx"
)

OUTPUT_DIRECTORY = PROJECT_ROOT / "data" / "processed"
PROFILE_FILE = OUTPUT_DIRECTORY / "data_profile.json"
MISSING_VALUES_FILE = OUTPUT_DIRECTORY / "missing_values.csv"

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


def calculate_sha256(file_path: Path) -> str:
    """Calculate a SHA-256 checksum without modifying the source file."""

    sha256 = hashlib.sha256()

    with file_path.open("rb") as file:
        for block in iter(lambda: file.read(1024 * 1024), b""):
            sha256.update(block)

    return sha256.hexdigest()


def validate_source_file(file_path: Path) -> None:
    """Confirm that the expected source file exists."""

    if not file_path.exists():
        raise FileNotFoundError(
            f"Source file was not found: {file_path}"
        )

    if file_path.suffix.lower() != ".xlsx":
        raise ValueError("The source file must be an XLSX workbook.")


def validate_schema(dataframe: pd.DataFrame) -> None:
    """Confirm that the source contains the expected columns."""

    actual_columns = dataframe.columns.tolist()

    if actual_columns != EXPECTED_COLUMNS:
        raise ValueError(
            "Unexpected source schema.\n"
            f"Expected: {EXPECTED_COLUMNS}\n"
            f"Actual:   {actual_columns}"
        )


def build_profile(dataframe: pd.DataFrame, checksum: str) -> dict:
    """Create the initial technical and data-quality profile."""

    invoices = dataframe["Invoice"].astype("string")
    cancelled = invoices.str.startswith("C", na=False)

    duplicated_rows = int(dataframe.duplicated().sum())
    negative_quantities = int((dataframe["Quantity"] < 0).sum())
    zero_quantities = int((dataframe["Quantity"] == 0).sum())
    nonpositive_prices = int((dataframe["UnitPrice"] <= 0).sum())

    profile = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "source": {
            "file_name": SOURCE_FILE.name,
            "sheet_name": "transactions_raw",
            "sha256": checksum,
        },
        "structure": {
            "row_count": int(len(dataframe)),
            "column_count": int(len(dataframe.columns)),
            "columns": dataframe.columns.tolist(),
        },
        "business_scope": {
            "unique_invoices": int(invoices.nunique(dropna=True)),
            "unique_products": int(
                dataframe["StockCode"].nunique(dropna=True)
            ),
            "unique_customers": int(
                dataframe["CustomerID"].nunique(dropna=True)
            ),
            "countries": int(
                dataframe["Country"].nunique(dropna=True)
            ),
            "minimum_invoice_date": str(
                dataframe["InvoiceDate"].min()
            ),
            "maximum_invoice_date": str(
                dataframe["InvoiceDate"].max()
            ),
        },
        "quality": {
            "duplicated_rows": duplicated_rows,
            "cancelled_transaction_lines": int(cancelled.sum()),
            "negative_quantity_rows": negative_quantities,
            "zero_quantity_rows": zero_quantities,
            "nonpositive_unit_price_rows": nonpositive_prices,
            "missing_values_by_column": {
                column: int(count)
                for column, count in dataframe.isna().sum().items()
            },
        },
    }

    return profile


def save_outputs(dataframe: pd.DataFrame, profile: dict) -> None:
    """Write profiling results outside the immutable raw directory."""

    OUTPUT_DIRECTORY.mkdir(parents=True, exist_ok=True)

    with PROFILE_FILE.open("w", encoding="utf-8") as file:
        json.dump(profile, file, indent=4, ensure_ascii=False)

    missing_values = pd.DataFrame(
        {
            "column": dataframe.columns,
            "missing_count": dataframe.isna().sum().values,
            "missing_percentage": (
                dataframe.isna().mean().values * 100
            ),
        }
    )

    missing_values.to_csv(
        MISSING_VALUES_FILE,
        index=False,
        encoding="utf-8",
    )


def main() -> None:
    logger.info("Starting source-data profiling")
    validate_source_file(SOURCE_FILE)

    checksum = calculate_sha256(SOURCE_FILE)
    logger.info("Source SHA-256: %s", checksum)

    dataframe = pd.read_excel(
        SOURCE_FILE,
        sheet_name="transactions_raw",
        dtype={
            "Invoice": "string",
            "StockCode": "string",
            "CustomerID": "string",
        },
    )

    validate_schema(dataframe)

    profile = build_profile(dataframe, checksum)
    save_outputs(dataframe, profile)

    logger.info("Rows profiled: %s", len(dataframe))
    logger.info("Profile saved to: %s", PROFILE_FILE)
    logger.info("Missing-value report saved to: %s", MISSING_VALUES_FILE)
    logger.info("Profiling completed successfully")


if __name__ == "__main__":
    main()
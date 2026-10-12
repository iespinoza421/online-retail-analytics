import logging
import os
from decimal import Decimal
from pathlib import Path

import pandas as pd
import pyodbc


PROJECT_ROOT = Path(__file__).resolve().parents[1]

SOURCE_FILE = (
    PROJECT_ROOT
    / "data"
    / "processed"
    / "invoice_product_summary.csv"
)

SQL_SERVER = os.getenv(
    "ONLINE_RETAIL_SQL_SERVER",
    "localhost",
)

SQL_DATABASE = os.getenv(
    "ONLINE_RETAIL_SQL_DATABASE",
    "OnlineRetailAnalytics",
)

ODBC_DRIVER = os.getenv(
    "ONLINE_RETAIL_ODBC_DRIVER",
    "ODBC Driver 18 for SQL Server",
)

EXPECTED_COLUMNS = [
    "AnalyticalLineID",
    "Invoice",
    "StockCode",
    "Description",
    "InvoiceDate",
    "UnitPrice",
    "CustomerID",
    "Country",
    "SourcePeriod",
    "TransactionType",
    "Quantity",
    "LineAmount",
    "SourceLineCount",
    "DuplicateCandidateLineCount",
    "FirstSourceRowNumber",
    "SourceRowNumbers",
    "HasMultipleSourceLines",
]

INSERT_STATEMENT = """
INSERT INTO stg.InvoiceProduct
(
    AnalyticalLineID,
    Invoice,
    StockCode,
    Description,
    InvoiceDate,
    UnitPrice,
    CustomerID,
    Country,
    SourcePeriod,
    TransactionType,
    Quantity,
    LineAmount,
    SourceLineCount,
    DuplicateCandidateLineCount,
    FirstSourceRowNumber,
    SourceRowNumbers,
    HasMultipleSourceLines
)
VALUES
(
    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
);
"""

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
)

logger = logging.getLogger(__name__)


def build_connection_string() -> str:
    """Build a secure local SQL Server connection string."""

    return (
        f"DRIVER={{{ODBC_DRIVER}}};"
        f"SERVER={SQL_SERVER};"
        f"DATABASE={SQL_DATABASE};"
        "Trusted_Connection=yes;"
        "Encrypt=yes;"
        "TrustServerCertificate=yes;"
    )


def load_analytical_file() -> pd.DataFrame:
    """Load and validate the analytical CSV."""

    if not SOURCE_FILE.exists():
        raise FileNotFoundError(
            "Analytical dataset was not found. "
            "Run build_analytical_dataset.py first."
        )

    dataframe = pd.read_csv(
        SOURCE_FILE,
        dtype={
            "Invoice": "string",
            "StockCode": "string",
            "Description": "string",
            "CustomerID": "string",
            "Country": "string",
            "SourcePeriod": "string",
            "TransactionType": "string",
            "SourceRowNumbers": "string",
        },
        parse_dates=["InvoiceDate"],
    )

    actual_columns = dataframe.columns.tolist()

    if actual_columns != EXPECTED_COLUMNS:
        raise ValueError(
            "Unexpected analytical dataset schema.\n"
            f"Expected: {EXPECTED_COLUMNS}\n"
            f"Actual:   {actual_columns}"
        )

    if dataframe.empty:
        raise ValueError(
            "Analytical dataset contains no records."
        )

    if dataframe["AnalyticalLineID"].duplicated().any():
        raise ValueError(
            "AnalyticalLineID contains duplicate values."
        )

    if dataframe["InvoiceDate"].isna().any():
        raise ValueError(
            "InvoiceDate contains invalid or missing values."
        )

    return dataframe


def parse_boolean(value: object) -> bool:
    """Convert CSV boolean representations safely."""

    if isinstance(value, bool):
        return value

    normalized = str(value).strip().lower()

    if normalized in {"true", "1", "yes"}:
        return True

    if normalized in {"false", "0", "no"}:
        return False

    raise ValueError(
        f"Invalid boolean value: {value}"
    )


def nullable_string(value: object) -> str | None:
    """Convert pandas missing values to database NULL."""

    if pd.isna(value):
        return None

    return str(value)


def dataframe_to_records(
    dataframe: pd.DataFrame,
) -> list[tuple]:
    """Convert pandas rows into SQL-compatible records."""

    records = []

    for row in dataframe.itertuples(index=False):
        record = (
            int(row.AnalyticalLineID),
            str(row.Invoice),
            str(row.StockCode),
            nullable_string(row.Description),
            row.InvoiceDate.to_pydatetime(),
            Decimal(str(row.UnitPrice)),
            nullable_string(row.CustomerID),
            str(row.Country),
            str(row.SourcePeriod),
            str(row.TransactionType),
            int(row.Quantity),
            Decimal(str(row.LineAmount)),
            int(row.SourceLineCount),
            int(row.DuplicateCandidateLineCount),
            int(row.FirstSourceRowNumber),
            str(row.SourceRowNumbers),
            parse_boolean(row.HasMultipleSourceLines),
        )

        records.append(record)

    return records


def start_audit_run(
    connection: pyodbc.Connection,
) -> int:
    """Create and commit the initial audit record."""

    cursor = connection.cursor()

    cursor.execute(
        """
        INSERT INTO audit.ETLRun
        (
            ProcessName,
            StartedAtUTC,
            RunStatus
        )
        OUTPUT INSERTED.ETLRunID
        VALUES
        (
            ?,
            SYSUTCDATETIME(),
            'STARTED'
        );
        """,
        "load_sql_server.py",
    )

    etl_run_id = int(cursor.fetchone()[0])

    connection.commit()
    cursor.close()

    return etl_run_id


def mark_audit_completed(
    connection: pyodbc.Connection,
    etl_run_id: int,
    source_row_count: int,
    staging_row_count: int,
    fact_row_count: int,
) -> None:
    """Mark a successful warehouse load."""

    cursor = connection.cursor()

    cursor.execute(
        """
        UPDATE audit.ETLRun
        SET
            CompletedAtUTC = SYSUTCDATETIME(),
            RunStatus = 'COMPLETED',
            SourceRowCount = ?,
            StagingRowCount = ?,
            FactRowCount = ?
        WHERE ETLRunID = ?;
        """,
        source_row_count,
        staging_row_count,
        fact_row_count,
        etl_run_id,
    )

    connection.commit()
    cursor.close()


def mark_audit_failed(
    connection: pyodbc.Connection,
    etl_run_id: int,
    error_message: str,
) -> None:
    """Mark a failed warehouse load."""

    cursor = connection.cursor()

    cursor.execute(
        """
        UPDATE audit.ETLRun
        SET
            CompletedAtUTC = SYSUTCDATETIME(),
            RunStatus = 'FAILED',
            ErrorMessage = ?
        WHERE ETLRunID = ?;
        """,
        error_message[:4000],
        etl_run_id,
    )

    connection.commit()
    cursor.close()


def load_staging_table(
    connection: pyodbc.Connection,
    records: list[tuple],
) -> None:
    """Replace staging contents with the current dataset."""

    cursor = connection.cursor()

    cursor.execute(
        "TRUNCATE TABLE stg.InvoiceProduct;"
    )

    cursor.fast_executemany = True

    cursor.executemany(
        INSERT_STATEMENT,
        records,
    )

    connection.commit()
    cursor.close()


def execute_warehouse_load(
    connection: pyodbc.Connection,
) -> dict:
    """Execute the dimensional warehouse procedure."""

    cursor = connection.cursor()

    cursor.execute(
        "EXEC etl.LoadWarehouse;"
    )

    result = cursor.fetchone()

    summary = {
        "staging_row_count": int(result[0]),
        "fact_row_count": int(result[1]),
        "total_quantity": int(result[2]),
        "total_line_amount": Decimal(
            str(result[3])
        ),
        "reconciliation_passed": bool(result[4]),
    }

    connection.commit()
    cursor.close()

    return summary


def main() -> None:
    """Load staging and populate the dimensional model."""

    logger.info("Starting SQL Server warehouse load")
    logger.info("Server: %s", SQL_SERVER)
    logger.info("Database: %s", SQL_DATABASE)

    dataframe = load_analytical_file()

    source_row_count = int(
        dataframe["SourceLineCount"].sum()
    )

    records = dataframe_to_records(dataframe)

    connection = pyodbc.connect(
        build_connection_string(),
        autocommit=False,
    )

    etl_run_id = start_audit_run(connection)

    try:
        logger.info(
            "Loading %s staging records",
            len(records),
        )

        load_staging_table(
            connection,
            records,
        )

        logger.info(
            "Executing dimensional warehouse load"
        )

        summary = execute_warehouse_load(
            connection
        )

        if not summary["reconciliation_passed"]:
            raise ValueError(
                "Warehouse reconciliation did not pass."
            )

        mark_audit_completed(
            connection=connection,
            etl_run_id=etl_run_id,
            source_row_count=source_row_count,
            staging_row_count=summary[
                "staging_row_count"
            ],
            fact_row_count=summary[
                "fact_row_count"
            ],
        )

        logger.info(
            "Staging rows: %s",
            summary["staging_row_count"],
        )

        logger.info(
            "Fact rows: %s",
            summary["fact_row_count"],
        )

        logger.info(
            "Total quantity: %s",
            summary["total_quantity"],
        )

        logger.info(
            "Total line amount: %s",
            summary["total_line_amount"],
        )

        logger.info(
            "ETL run ID: %s",
            etl_run_id,
        )

        logger.info(
            "SQL Server warehouse load completed"
        )

    except Exception as error:
        connection.rollback()

        try:
            mark_audit_failed(
                connection,
                etl_run_id,
                str(error),
            )
        except Exception:
            logger.exception(
                "Unable to update failed audit record"
            )

        raise

    finally:
        connection.close()


if __name__ == "__main__":
    main()
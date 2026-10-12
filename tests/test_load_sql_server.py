from decimal import Decimal

import pandas as pd
import pytest

from src.load_sql_server import (
    build_connection_string,
    dataframe_to_records,
    nullable_string,
    parse_boolean,
)


def build_test_dataframe() -> pd.DataFrame:
    """Create one analytical row for SQL conversion tests."""

    return pd.DataFrame(
        [
            {
                "AnalyticalLineID": 1,
                "Invoice": "10001",
                "StockCode": "A",
                "Description": pd.NA,
                "InvoiceDate": pd.Timestamp(
                    "2011-01-01 10:30:00"
                ),
                "UnitPrice": 2.50,
                "CustomerID": pd.NA,
                "Country": "United Kingdom",
                "SourcePeriod": "Test",
                "TransactionType": "SALE",
                "Quantity": 2,
                "LineAmount": 5.00,
                "SourceLineCount": 1,
                "DuplicateCandidateLineCount": 0,
                "FirstSourceRowNumber": 2,
                "SourceRowNumbers": "2",
                "HasMultipleSourceLines": False,
            }
        ]
    )


def test_parse_boolean_values() -> None:
    assert parse_boolean(True) is True
    assert parse_boolean(False) is False
    assert parse_boolean("true") is True
    assert parse_boolean("1") is True
    assert parse_boolean("false") is False
    assert parse_boolean("0") is False


def test_parse_boolean_rejects_invalid_value() -> None:
    with pytest.raises(
        ValueError,
        match="Invalid boolean value",
    ):
        parse_boolean("maybe")


def test_nullable_string() -> None:
    assert nullable_string(pd.NA) is None
    assert nullable_string(None) is None
    assert nullable_string("12345") == "12345"


def test_dataframe_to_records() -> None:
    records = dataframe_to_records(
        build_test_dataframe()
    )

    assert len(records) == 1

    record = records[0]

    assert record[0] == 1
    assert record[1] == "10001"
    assert record[3] is None
    assert record[5] == Decimal("2.5")
    assert record[6] is None
    assert record[10] == 2
    assert record[11] == Decimal("5.0")
    assert record[16] is False


def test_connection_string_uses_windows_authentication() -> None:
    connection_string = build_connection_string()

    assert "Trusted_Connection=yes" in connection_string
    assert "Encrypt=yes" in connection_string
    assert "TrustServerCertificate=yes" in connection_string
    assert "PWD=" not in connection_string
    assert "UID=" not in connection_string
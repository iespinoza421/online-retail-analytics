import pandas as pd
import pytest

from src.transform_transactions import (
    add_duplicate_indicator,
    classify_transactions,
    validate_transformation,
)


def build_test_data() -> pd.DataFrame:
    """Create representative rows for every classification."""

    return pd.DataFrame(
        [
            {
                "SourceRowNumber": 2,
                "Invoice": "10001",
                "StockCode": "A",
                "Description": "Valid product",
                "Quantity": 2,
                "InvoiceDate": pd.Timestamp("2011-01-01"),
                "UnitPrice": 5.00,
                "CustomerID": "12345",
                "Country": "United Kingdom",
                "SourcePeriod": "Test",
            },
            {
                "SourceRowNumber": 3,
                "Invoice": "C10002",
                "StockCode": "B",
                "Description": "Returned product",
                "Quantity": -1,
                "InvoiceDate": pd.Timestamp("2011-01-02"),
                "UnitPrice": 4.00,
                "CustomerID": "12345",
                "Country": "United Kingdom",
                "SourcePeriod": "Test",
            },
            {
                "SourceRowNumber": 4,
                "Invoice": "10003",
                "StockCode": "C",
                "Description": "Promotional item",
                "Quantity": 1,
                "InvoiceDate": pd.Timestamp("2011-01-03"),
                "UnitPrice": 0.00,
                "CustomerID": "12345",
                "Country": "Spain",
                "SourcePeriod": "Test",
            },
            {
                "SourceRowNumber": 5,
                "Invoice": "10004",
                "StockCode": "D",
                "Description": "damaged",
                "Quantity": -5,
                "InvoiceDate": pd.Timestamp("2011-01-04"),
                "UnitPrice": 0.00,
                "CustomerID": pd.NA,
                "Country": "United Kingdom",
                "SourcePeriod": "Test",
            },
            {
                "SourceRowNumber": 6,
                "Invoice": "A10005",
                "StockCode": "B",
                "Description": "Adjust bad debt",
                "Quantity": 1,
                "InvoiceDate": pd.Timestamp("2011-01-05"),
                "UnitPrice": -100.00,
                "CustomerID": pd.NA,
                "Country": "United Kingdom",
                "SourcePeriod": "Test",
            },
        ]
    )


def test_every_documented_classification() -> None:
    dataframe = classify_transactions(build_test_data())

    assert dataframe["TransactionType"].tolist() == [
        "SALE",
        "CANCELLATION",
        "FREE_ITEM",
        "INVENTORY_ADJUSTMENT",
        "FINANCIAL_ADJUSTMENT",
    ]


def test_line_amount_is_calculated() -> None:
    dataframe = classify_transactions(build_test_data())

    assert dataframe["LineAmount"].tolist() == [
        10.00,
        -4.00,
        0.00,
        0.00,
        -100.00,
    ]


def test_commercial_indicator() -> None:
    dataframe = classify_transactions(build_test_data())

    assert dataframe["IsCommercialTransaction"].tolist() == [
        True,
        True,
        True,
        False,
        False,
    ]


def test_duplicate_candidates_are_flagged_without_removal() -> None:
    dataframe = build_test_data()

    duplicated_row = dataframe.iloc[[0]].copy()
    duplicated_row["SourceRowNumber"] = 7

    dataframe = pd.concat(
        [dataframe, duplicated_row],
        ignore_index=True,
    )

    result = add_duplicate_indicator(dataframe)

    assert len(result) == 6
    assert int(result["IsExactDuplicateCandidate"].sum()) == 2


def test_validation_accepts_reconciled_data() -> None:
    source = build_test_data()
    transformed = classify_transactions(source)

    validate_transformation(source, transformed)


def test_validation_rejects_missing_rows() -> None:
    source = build_test_data()
    transformed = classify_transactions(source).iloc[:-1].copy()

    with pytest.raises(ValueError, match="row counts"):
        validate_transformation(source, transformed)
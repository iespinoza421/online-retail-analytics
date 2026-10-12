import pandas as pd
import pytest

from src.build_analytical_dataset import (
    build_invoice_product_summary,
    validate_aggregation,
)


def build_test_data() -> pd.DataFrame:
    """Create commercial lines for aggregation tests."""

    return pd.DataFrame(
        [
            {
                "SourceRowNumber": 2,
                "Invoice": "10001",
                "StockCode": "A",
                "Description": "Product A",
                "Quantity": 1,
                "InvoiceDate": pd.Timestamp(
                    "2011-01-01 10:00:00"
                ),
                "UnitPrice": 2.00,
                "CustomerID": "12345",
                "Country": "United Kingdom",
                "SourcePeriod": "Test",
                "TransactionType": "SALE",
                "LineAmount": 2.00,
                "IsExactDuplicateCandidate": True,
            },
            {
                "SourceRowNumber": 3,
                "Invoice": "10001",
                "StockCode": "A",
                "Description": "Product A",
                "Quantity": 2,
                "InvoiceDate": pd.Timestamp(
                    "2011-01-01 10:00:00"
                ),
                "UnitPrice": 2.00,
                "CustomerID": "12345",
                "Country": "United Kingdom",
                "SourcePeriod": "Test",
                "TransactionType": "SALE",
                "LineAmount": 4.00,
                "IsExactDuplicateCandidate": True,
            },
            {
                "SourceRowNumber": 4,
                "Invoice": "10001",
                "StockCode": "B",
                "Description": "Product B",
                "Quantity": 1,
                "InvoiceDate": pd.Timestamp(
                    "2011-01-01 10:00:00"
                ),
                "UnitPrice": 5.00,
                "CustomerID": "12345",
                "Country": "United Kingdom",
                "SourcePeriod": "Test",
                "TransactionType": "SALE",
                "LineAmount": 5.00,
                "IsExactDuplicateCandidate": False,
            },
        ]
    )


def test_same_invoice_product_is_consolidated() -> None:
    source = build_test_data()

    analytical = build_invoice_product_summary(source)

    assert len(analytical) == 2

    product_a = analytical.loc[
        analytical["StockCode"] == "A"
    ].iloc[0]

    assert product_a["Quantity"] == 3
    assert product_a["LineAmount"] == 6.00
    assert product_a["SourceLineCount"] == 2


def test_source_row_lineage_is_preserved() -> None:
    analytical = build_invoice_product_summary(
        build_test_data()
    )

    product_a = analytical.loc[
        analytical["StockCode"] == "A"
    ].iloc[0]

    assert product_a["FirstSourceRowNumber"] == 2
    assert product_a["SourceRowNumbers"] == "2,3"
    assert bool(product_a["HasMultipleSourceLines"]) is True


def test_aggregation_reconciliation_passes() -> None:
    source = build_test_data()

    analytical = build_invoice_product_summary(source)

    validate_aggregation(
        source,
        analytical,
    )


def test_revenue_difference_is_rejected() -> None:
    source = build_test_data()

    analytical = build_invoice_product_summary(source)

    analytical.loc[
        analytical.index[0],
        "LineAmount",
    ] += 1.00

    with pytest.raises(
        ValueError,
        match="Revenue reconciliation failed",
    ):
        validate_aggregation(
            source,
            analytical,
        )


def test_quantity_difference_is_rejected() -> None:
    source = build_test_data()

    analytical = build_invoice_product_summary(source)

    analytical.loc[
        analytical.index[0],
        "Quantity",
    ] += 1

    with pytest.raises(
        ValueError,
        match="Quantity reconciliation failed",
    ):
        validate_aggregation(
            source,
            analytical,
        )
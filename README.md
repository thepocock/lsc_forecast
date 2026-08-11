# lsc_forecast
Sample SQL - Circa 2015

This T-SQL model was built to forecast the eventual performance of digital marketing leads before those leads had enough time to fully mature through the sales funnel.

The model first analyzes historical cohorts to determine how long leads typically take to progress from creation to application submission. It converts that history into a cumulative completion curve showing the percentage of expected submissions normally observed at each lead age. Current lead cohorts can then be compared against that curve to estimate their eventual number of submissions.

The forecast continues beyond submission by applying historical downstream performance to estimate settlements, production, conversion rates, and average premium. Results are produced alongside actual performance and historical benchmarks so forecast accuracy and current performance can be compared over time.

The script also performs a historical backfill, repeatedly advancing the observation date and recalculating the forecast as if it were being run on each prior date. This creates a series of forecast snapshots that can be used to evaluate how the model behaved as cohorts matured.

The model includes:

Historical cohort and lead-maturity analysis Days-to-submission distribution and cumulative completion curves Forecasting of incomplete lead cohorts Actual vs. forecast vs. historical baseline reporting Submission, settlement, conversion, production, and premium metrics Lead-source-specific forecasting Rolling historical reference periods Historical forecast reconstruction for backtesting Multi-stage transformations implemented through chained CTEs Automated persistence of forecast snapshots for downstream reporting and analysis

Portfolio note: This is an anonymized version of a production-oriented analytical model. Company names, database objects, identifiers, source values, and proprietary business rules have been removed or changed.

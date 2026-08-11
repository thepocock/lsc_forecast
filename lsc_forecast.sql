TRUNCATE TABLE [Portfolio].[dbo].[ForecastHistory]

DECLARE @STARTDATE datetime = '2019-01-01'
DECLARE @ENDDATE datetime = '2019-01-02'
DECLARE @INCREMENT int = 1

-- Illustrative portfolio values.
-- Original production tuning values have been changed.
DECLARE @REFERENCE_LOOKBACK_START int = 420
DECLARE @REFERENCE_LOOKBACK_END int = 120
DECLARE @MATURITY_WINDOW int = 84
DECLARE @EARLY_AGE_CUTOFF int = 30
DECLARE @EARLY_ADJUSTMENT_A float = .94
DECLARE @EARLY_ADJUSTMENT_B float = .985

;

DECLARE @SOURCES TABLE (
	ID [int] IDENTITY(1,1),
	SourceCode [varchar](10),
	SourceDescription [varchar](100)
)

INSERT INTO @SOURCES
	SELECT
		DISTINCT
		SourceCode
		, SourceDescription
	FROM [dbo].[FunnelActivity] A
	INNER JOIN [Reference].[SourceMap] B
		ON B.SourceCode = A.SourceCode
	WHERE
		Stage1Complete IS NOT NULL
		AND SourceCode IN ('A1')
		AND CreatedDate BETWEEN @STARTDATE AND (
			SELECT MAX(OutcomeDate)
			FROM [dbo].[FunnelActivity]
			WHERE Stage1Complete IS NOT NULL
		)

DECLARE @ORGSD date = @STARTDATE
DECLARE @ORGED date = @ENDDATE
DECLARE @INTERVAL int = 1
DECLARE @LOOP int = 1

WHILE @LOOP !> (SELECT MAX(ID) FROM @SOURCES)
BEGIN

	WHILE CAST(@ENDDATE AS date) <= (
		SELECT MAX(OutcomeDate)
		FROM [Analytics].[dbo].[FunnelActivity]
		WHERE Stage1Complete IS NOT NULL
	)
	BEGIN

		WITH [Distribution] AS (
			SELECT
				DATEDIFF(dd, CreatedDate, OutcomeDate) AS 'DaysToStage1'
				, COUNT(OutcomeID) AS 'Stage1Count'
			FROM [Analytics].[dbo].[FunnelActivity] A
			INNER JOIN @SOURCES B
				ON B.SourceCode = A.SourceCode
				AND B.ID = @LOOP
			WHERE
				OutcomeID IS NOT NULL
				AND RecordID IS NOT NULL
				AND CAST(CreatedDate AS date) <= CAST(OutcomeDate AS date)
				AND CreatedDate BETWEEN
					DATEADD(dd, -@REFERENCE_LOOKBACK_START, @STARTDATE)
					AND DATEADD(dd, -@REFERENCE_LOOKBACK_END, @STARTDATE)
				AND CAST([OutcomeDate] AS date) <=
					CAST([CreatedDate] + @MATURITY_WINDOW AS date)
				AND Stage1Complete = 1
			GROUP BY DATEDIFF(dd, CreatedDate, OutcomeDate)
		),

		[RunningTotal] AS (
			SELECT
				1 AS 'HardCode'
				, A.DaysToStage1
				, A.Stage1Count
				, SUM(B.Stage1Count) AS 'RunningTotal'
			FROM [Distribution] A
			INNER JOIN [Distribution] B
				ON B.DaysToStage1 <= A.DaysToStage1
			GROUP BY
				A.DaysToStage1
				, A.Stage1Count
		),

		[GrandTotal] AS (
			SELECT
				1 AS 'HardCode'
				, SUM(Stage1Count) AS 'GrandTotal'
			FROM [Distribution]
		),

		[Forecast] AS (
			SELECT
				A.DaysToStage1
				, CASE
					WHEN B.GrandTotal = 0
						THEN 0
					ELSE CAST(A.RunningTotal AS float) / B.GrandTotal
				END AS 'CompletionPCT'
			FROM [RunningTotal] A
			INNER JOIN [GrandTotal] B
				ON B.HardCode = A.HardCode
		),

		[Records] AS (
			SELECT
				RecordID
				, DATEDIFF(dd, CreatedDate, GETDATE()) AS 'RecordAge'
				, [RecordCount]
				, [Stage1Complete]
				, [Stage2Complete]
				, [ValueAmount]
			FROM [Analytics].[dbo].[FunnelActivity] A
			INNER JOIN @SOURCES B
				ON B.SourceCode = A.SourceCode
				AND B.ID = @LOOP
			WHERE
				RecordID IS NOT NULL
				AND CreatedDate BETWEEN @STARTDATE AND @ENDDATE
		),

		[T] AS (
			SELECT
				RecordAge
				, ISNULL(CompletionPCT,1) AS 'CompletionPCT'
				, SUM(RecordCount) AS 'Records'
				, ISNULL(SUM(Stage1Complete),0) AS 'CurrentStage1'
			FROM [Records] A
			LEFT JOIN [Forecast] B
				ON B.DaysToStage1 = A.RecordAge
			GROUP BY
				RecordAge
				, CompletionPCT
		),

		[T1] AS (
			SELECT
				RecordAge
				, CurrentStage1
				, CASE
					WHEN CompletionPCT = 0
						THEN 0
					ELSE CurrentStage1 / CompletionPCT
				END AS 'Forecast'
			FROM [T]
		),

		[Publish] AS (
			SELECT
				1 AS 'HardCode'
				, 'Actual' AS 'DataType'
				, SUM(CurrentStage1) AS 'Stage1Count'
			FROM [T1]

			UNION

			SELECT
				1
				, 'Forecast'
				, SUM(
					CASE
						WHEN RecordAge < @EARLY_AGE_CUTOFF
							AND Forecast <> 0
							THEN (Forecast / @EARLY_ADJUSTMENT_A)
								/ @EARLY_ADJUSTMENT_B
						WHEN RecordAge < @EARLY_AGE_CUTOFF
							AND Forecast = 0
							THEN 0
						ELSE CurrentStage1
					END
				)
			FROM [T1]
		),

		[HistoricAggRecords] AS (
			SELECT
				1 AS 'HardCode'
				, SourceCode
				, SourceDescription
				, SUM(RecordCount) AS 'HistRecords'
				, SUM(Stage1Complete) AS 'HistStage1'
				, SUM(Stage2Complete) AS 'HistStage2'

				, CASE
					WHEN SUM(RecordCount) = 0
						THEN 0
					ELSE SUM(Stage1Complete) / SUM(RecordCount)
				END AS 'HistStage1PCT'

				, SUM(ValueAmount) AS 'HistValue'

				, CASE
					WHEN SUM(Stage1Complete) = 0
						THEN 0
					ELSE SUM(Stage2Complete) / SUM(Stage1Complete)
				END AS 'HistStage2PCT'

				, CASE
					WHEN SUM(RecordCount) = 0
						THEN 0
					ELSE SUM(Stage2Complete) / SUM(RecordCount)
				END AS 'HistConversionPCT'

			FROM (
				SELECT
					RecordID
					, B.SourceCode
					, B.SourceDescription
					, DATEDIFF(dd, CreatedDate, GETDATE()) AS 'RecordAge'
					, [RecordCount]
					, [Stage1Complete]
					, [Stage2Complete]
					, [ValueAmount]
				FROM [dbo].[FunnelActivity] A
				INNER JOIN @SOURCES B
					ON B.SourceCode = A.SourceCode
					AND B.ID = @LOOP
				WHERE
					RecordID IS NOT NULL
					AND CreatedDate BETWEEN
						DATEADD(dd, -@REFERENCE_LOOKBACK_START, @STARTDATE)
						AND DATEADD(dd, -@REFERENCE_LOOKBACK_END, @STARTDATE)
			) A

			GROUP BY
				SourceCode
				, SourceDescription
		),

		[ActualAggRecords] AS (
			SELECT
				1 AS 'HardCode'
				, SUM(RecordCount) AS 'ActRecords'
				, SUM(Stage1Complete) AS 'ActStage1'
				, SUM(Stage2Complete) AS 'ActStage2'

				, CASE
					WHEN SUM(RecordCount) = 0
						THEN 0
					ELSE SUM(Stage1Complete) / SUM(RecordCount)
				END AS 'ActStage1PCT'

				, SUM(ValueAmount) AS 'ActValue'

				, CASE
					WHEN SUM(Stage1Complete) = 0
						THEN 0
					ELSE SUM(Stage2Complete) / SUM(Stage1Complete)
				END AS 'ActStage2PCT'

				, CASE
					WHEN SUM(RecordCount) = 0
						THEN 0
					ELSE SUM(Stage2Complete) / SUM(RecordCount)
				END AS 'ActConversionPCT'

			FROM [Records]
		),

		[Published] AS (
			SELECT
				DataType
				, SourceCode
				, SourceDescription
				, ActRecords AS 'Records'
				, CAST(Stage1Count AS int) AS 'Stage1Count'

				, CAST(
					CASE
						WHEN DataType = 'Actual'
							THEN ActStage2
						WHEN DataType = 'Forecast'
							THEN Stage1Count * HistStage2PCT
					END
				AS int) AS 'Stage2Count'

				, CASE
					WHEN DataType = 'Actual'
						THEN ActValue
					WHEN DataType = 'Forecast'
						AND (
							HistStage2 <> 0
							AND Stage1Count <> 0
							AND HistStage2PCT <> 0
						)
						THEN
							(HistValue / HistStage2)
							* Stage1Count
							* HistStage2PCT
					ELSE 0
				END AS 'ValueAmount'

				, CASE
					WHEN DataType = 'Actual'
						THEN ActStage1PCT
					WHEN DataType = 'Forecast'
						AND ActRecords <> 0
						THEN Stage1Count / ActRecords
					ELSE 0
				END AS 'Stage1PCT'

				, CASE
					WHEN DataType = 'Actual'
						THEN ActStage2PCT
					WHEN DataType = 'Forecast'
						AND (
							Stage1Count <> 0
							AND HistStage2PCT <> 0
						)
						THEN
							(Stage1Count * HistStage2PCT)
							/ Stage1Count
					ELSE 0
				END AS 'Stage2PCT'

				, CASE
					WHEN DataType = 'Actual'
						THEN ActConversionPCT
					WHEN DataType = 'Forecast'
						AND (
							ActRecords <> 0
							AND HistStage2PCT <> 0
						)
						THEN
							(Stage1Count * HistStage2PCT)
							/ ActRecords
					ELSE 0
				END AS 'ConversionPCT'

				, CASE
					WHEN DataType = 'Actual'
						AND ActStage2 <> 0
						THEN ActValue / ActStage2

					WHEN DataType = 'Actual'
						AND ActStage2 = 0
						THEN 0

					WHEN DataType = 'Forecast'
						AND (
							HistStage2 <> 0
							AND Stage1Count <> 0
							AND HistStage2PCT <> 0
						)
						THEN
							(
								(HistValue / HistStage2)
								* Stage1Count
								* HistStage2PCT
							)
							/ (Stage1Count * HistStage2PCT)

					ELSE 0
				END AS 'AverageValue'

			FROM [Publish] A

			LEFT JOIN [HistoricAggRecords] B
				ON B.HardCode = A.HardCode
				AND DataType <> 'Historic'

			LEFT JOIN [ActualAggRecords] C
				ON C.HardCode = A.HardCode

			UNION

			SELECT
				'Historic'
				, SourceCode
				, SourceDescription
				, CAST(
					(HistRecords / 365)
					* DATEDIFF(dd, @STARTDATE, @ENDDATE)
				AS int)

				, CAST(
					(HistStage1 / 365)
					* DATEDIFF(dd, @STARTDATE, @ENDDATE)
				AS int)

				, CAST(
					(HistStage2 / 365)
					* DATEDIFF(dd, @STARTDATE, @ENDDATE)
				AS int)

				, (HistValue / 365)
					* DATEDIFF(dd, @STARTDATE, @ENDDATE)

				, HistStage1PCT
				, HistStage2PCT
				, HistConversionPCT

				, CASE
					WHEN HistStage2 = 0
						THEN 0
					ELSE HistValue / HistStage2
				END

			FROM [HistoricAggRecords]
		)

		INSERT INTO [Portfolio].[dbo].[ForecastHistory]
			SELECT
				@INTERVAL
				, CAST(@STARTDATE AS date)
				, [DataType]
				, [SourceCode]
				, [SourceDescription]
				, @INCREMENT

				, CASE
					WHEN DataType = 'Actual'
						THEN 1
					WHEN DataType = 'Historic'
						THEN 2
					WHEN DataType = 'Forecast'
						THEN 3
				END AS 'Ordered'

				, ISNULL([Records], 0)
				, ISNULL([Stage1Count], 0)
				, ISNULL([Stage2Count], 0)
				, ISNULL([ValueAmount], 0)
				, ISNULL([Stage1PCT], 0)
				, ISNULL([Stage2PCT], 0)
				, ISNULL([ConversionPCT], 0)
				, ISNULL([AverageValue], 0)
				, GETDATE() AS 'InsertDate'

			FROM [Published]

			ORDER BY
				CASE
					WHEN DataType = 'Actual'
						THEN 1
					WHEN DataType = 'Historic'
						THEN 2
					WHEN DataType = 'Forecast'
						THEN 3
				END

		SET @STARTDATE = @STARTDATE + @INCREMENT
		SET @ENDDATE = @ENDDATE + @INCREMENT
		SET @INTERVAL = @INTERVAL + 1

		WAITFOR DELAY '00:00:01'

	END

	SET @LOOP = @LOOP + 1
	SET @INTERVAL = 1
	SET @STARTDATE = @ORGSD
	SET @ENDDATE = @ORGED

	WAITFOR DELAY '00:00:30'

END

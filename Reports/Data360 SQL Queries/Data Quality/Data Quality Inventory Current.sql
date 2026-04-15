let
    // Build full table reference dynamically
    FullTableName = 
        "`" & BillingProjectID & "." & DatasetName & ".inventory_current`",

    // Build dynamic SQL
    SQLStatement = 
		" Select * FROM  " & FullTableName & " 
		",
    // Connect to BigQuery using parameter
    Source =
        Value.NativeQuery(
            GoogleBigQuery.Database(
                [BillingProject = BillingProjectID, UseStorageApi = false]
            ){[Name = BillingProjectID]}[Data],
            SQLStatement,
            null,
            [EnableFolding = true]
        )
in
    Source
let
    // Dynamic Parameters
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    // Dynamic table path
    ShipmentsTable = "`" & BillingProject & "." & Dataset & ".shipments`",

    SQLQuery = "
SELECT
  DISTINCT(moves.order_channel_id),
  moves.order_channel_name
FROM " & ShipmentsTable & "
LEFT JOIN UNNEST(moves) as moves
WHERE order_channel_id IS NOT NULL
",

    Source = Value.NativeQuery(
        GoogleBigQuery.Database(
            [BillingProject = BillingProject, UseStorageApi = false]
        ){[Name = BillingProject]}[Data],
        SQLQuery,
        null,
        [EnableFolding = true]
    )

in
    Source
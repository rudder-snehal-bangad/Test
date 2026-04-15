let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,
 
    BasePath = "`" & BillingProject & "." & Dataset & ".products`",
 
    SQLQuery = "
WITH base AS (
  SELECT
    product.id,
    TRIM(product.code) AS product_code,
    product.active,
    attr.attribute_name,
    attr.value AS attribute_value
  FROM " & BasePath & " product
  LEFT JOIN UNNEST(product.attributes) AS attr
),
filtered AS (
  SELECT *
  FROM base
  QUALIFY
    COUNT(*) OVER (PARTITION BY product_code) = 1
    OR (
      COUNT(*) OVER (PARTITION BY product_code) > 1
      AND active = TRUE
    )
),
attr_map AS (
  SELECT
    attribute_name,
    DENSE_RANK() OVER (ORDER BY attribute_name) AS slot_index,
    CONCAT('Attribute ', CAST(DENSE_RANK() OVER (ORDER BY attribute_name) AS STRING)) AS attribute_slot
  FROM (
    SELECT DISTINCT attribute_name
    FROM filtered
    WHERE attribute_name IS NOT NULL
  )
)
SELECT
  f.id,
  f.product_code,
  m.attribute_slot,
  f.attribute_value
FROM filtered f
LEFT JOIN attr_map m
  ON f.attribute_name = m.attribute_name
",
 
    Source =
        Value.NativeQuery(
            GoogleBigQuery.Database(
                [BillingProject = BillingProject, UseStorageApi = false]
            ){[Name = BillingProject]}[Data],
            SQLQuery,
            null,
            [EnableFolding = true]
        ),
 
    #"Replace Null Slot" =
        Table.ReplaceValue(Source, null, "attribute_0", Replacer.ReplaceValue, {"attribute_slot"}),
 
    #"Replace Null Value" =
        Table.ReplaceValue(#"Replace Null Slot", null, "(Blank)", Replacer.ReplaceValue, {"attribute_value"}),
    #"Replaced Value" = Table.ReplaceValue(#"Replace Null Value","attribute_0","Attribute 0",Replacer.ReplaceText,{"attribute_slot"}),
 
    #"Pivoted Slot" =
        Table.Pivot(
            #"Replaced Value",
            List.Distinct(#"Replaced Value"[attribute_slot]),
            "attribute_slot",
            "attribute_value"
        )
in
    #"Pivoted Slot"

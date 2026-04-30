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
    CONCAT('attribute_', CAST(DENSE_RANK() OVER (ORDER BY attribute_name) AS STRING)) AS attribute_slot
  FROM (
    SELECT DISTINCT attribute_name
    FROM filtered
    WHERE attribute_name IS NOT NULL
  )
)

SELECT
  f.id,
  f.product_code,
  COALESCE(m.attribute_slot,'attribute_0') AS attribute_name,
  f.attribute_value,
  CONCAT(
    REPEAT(
      CHR(8203),
      DENSE_RANK() OVER (ORDER BY f.attribute_name ASC)
    ),
    f.attribute_value
  ) AS attribute_value_sorted
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

    // Attribute name cleanup
    #"Replaced _ with space" =
        Table.ReplaceValue(Source, "_", " ", Replacer.ReplaceText, {"attribute_name"}),

    #"Proper Case" =
        Table.TransformColumns(
            #"Replaced _ with space",
            {{"attribute_name", Text.Proper, type text}}
        ),

    #"Replaced - with space" =
        Table.ReplaceValue(#"Proper Case", "-", " ", Replacer.ReplaceText, {"attribute_name"}),

    #"Fix SKU" =
        Table.ReplaceValue(#"Replaced - with space", "Sku", "SKU", Replacer.ReplaceText, {"attribute_name"}),

    #"Fix BA" =
        Table.ReplaceValue(#"Fix SKU", "Ba", "BA", Replacer.ReplaceText, {"attribute_name"}),

    #"Replace Null Attribute Name" =
        Table.ReplaceValue(#"Fix BA", null, "(Blank)", Replacer.ReplaceValue, {"attribute_name"}),

    // Pivot / Unpivot logic
    #"Pivoted Column" =
        Table.Pivot(
            #"Replace Null Attribute Name",
            List.Distinct(#"Replace Null Attribute Name"[attribute_name]),
            "attribute_name",
            "attribute_value"
        ),

    #"Replace Null Values" =
        Table.ReplaceValue(
            #"Pivoted Column",
            null,
            "(Blank)",
            Replacer.ReplaceValue,
            List.Skip(Table.ColumnNames(#"Pivoted Column"), 2)
        ),

    #"Unpivoted Other Columns" =
        Table.UnpivotOtherColumns(
            #"Replace Null Values",
            {"id", "product_code"},
            "attribute_name",
            "attribute_value"
        ),
    #"Added Attribute Sort" =
    Table.AddColumn(
        #"Replace Null Attribute Name",
        "attribute_sort",
        each try Number.From(Text.AfterDelimiter([attribute_name], " ")) otherwise -1,
        Int64.Type
    )
in
    #"Added Attribute Sort"
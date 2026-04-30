let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    SQLQuery = "
WITH base AS (
  SELECT
    product.id,
    TRIM(product.code) AS product_code,
    product.active,
    attr.attribute_name AS attr_name,
    attr.value AS attribute_value
  FROM " & BillingProject & "." & Dataset & ".products product
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
    attr_name,
    DENSE_RANK() OVER (ORDER BY attr_name) AS slot_index,
    CONCAT('attribute_', CAST(DENSE_RANK() OVER (ORDER BY attr_name) AS STRING)) AS attribute_name
  FROM (
    SELECT DISTINCT attr_name
    FROM filtered
    WHERE attr_name IS NOT NULL
  )
)
SELECT
  f.id,
  f.product_code,
  m.attribute_name,
  f.attribute_value
FROM filtered f
LEFT JOIN attr_map m
  ON f.attr_name = m.attr_name
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

    #"Replace Null Attribute Slot" =
        Table.ReplaceValue(Source,null,"attribute_0",Replacer.ReplaceValue,{"attribute_name"}),

    #"Replace Underscore" =
        Table.ReplaceValue(#"Replace Null Attribute Slot","_"," ",Replacer.ReplaceText,{"attribute_name"}),

    #"Capitalized Each Word" =
        Table.TransformColumns(#"Replace Underscore",{{"attribute_name", Text.Proper, type text}}),

    #"Replace Hyphen" =
        Table.ReplaceValue(#"Capitalized Each Word","-"," ",Replacer.ReplaceText,{"attribute_name"}),

    #"Fix SKU" =
        Table.ReplaceValue(#"Replace Hyphen","Sku","SKU",Replacer.ReplaceText,{"attribute_name"}),

    #"Fix BA" =
        Table.ReplaceValue(#"Fix SKU","Ba","BA",Replacer.ReplaceText,{"attribute_name"}),

    #"Replace Null Attribute Value" =
        Table.ReplaceValue(#"Fix BA",null,"(Blank)",Replacer.ReplaceValue,{"attribute_value"}),

    #"Replace Null Attribute Name" =
        Table.ReplaceValue(#"Replace Null Attribute Value",null,"(Blank)",Replacer.ReplaceValue,{"attribute_name"}),

    #"Added Attribute Sort" =
    Table.AddColumn(
        #"Replace Null Attribute Name",
        "attribute_sort",
        each try Number.From(Text.AfterDelimiter([attribute_name], " ")) otherwise -1,
        Int64.Type
    )
in
    #"Added Attribute Sort"
let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    SQLQuery = "
WITH base AS (
  SELECT
    product.id,
    TRIM(product.code) AS product_code,
    product.active,
    attr.attribute_name,
    attr.value AS attribute_value
  FROM "  & BillingProject & "." & Dataset & ".products product
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
  m.attribute_slot as product_attribute,
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
    #"Replaced Value" = Table.ReplaceValue(Source,null,"attribute_0",Replacer.ReplaceValue,{"product_attribute"}),
    #"Replaced Value1" = Table.ReplaceValue(#"Replaced Value","_"," ",Replacer.ReplaceText,{"product_attribute"}),
    #"Capitalized Each Word" = Table.TransformColumns(#"Replaced Value1",{{"product_attribute", Text.Proper, type text}}),
    #"Replaced Value2" = Table.ReplaceValue(#"Capitalized Each Word","-"," ",Replacer.ReplaceText,{"product_attribute"}),
    #"Replaced Value3" = Table.ReplaceValue(#"Replaced Value2","Sku","SKU",Replacer.ReplaceText,{"product_attribute"}),
    #"Replaced Value4" = Table.ReplaceValue(#"Replaced Value3","Ba","BA",Replacer.ReplaceText,{"product_attribute"})
in
    #"Replaced Value4"
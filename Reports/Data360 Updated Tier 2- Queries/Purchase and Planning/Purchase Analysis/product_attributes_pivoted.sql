let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = BillingProject & "." & Dataset,

    SQLQuery ="
    WITH base AS (
                SELECT
                    product.id,
                    TRIM(product.code) AS product_code,
                    active,
                    attr.attribute_name,
                    attr.value AS attribute_value
                FROM `" & BasePath & ".products` product
                LEFT JOIN UNNEST(attributes) AS attr
                WHERE category_root_name NOT IN (
                    'SERVICE',
                    'To be Classified',
                    'PACKAGING',
                    'OPTIONS_HIDDEN_PRODUCT'
                )
            )
            SELECT *
            FROM base
            QUALIFY
                COUNT(*) OVER (PARTITION BY product_code) = 1
                OR (
                    COUNT(*) OVER (PARTITION BY product_code) > 1
                    AND active = TRUE
                )"
	,
	Source = Value.NativeQuery(
        GoogleBigQuery.Database(
            [BillingProject = BillingProject, UseStorageApi = false]
        ){[Name = BillingProject]}[Data],
        SQLQuery,
        null,
        [EnableFolding = true]
    ),
    /* ---------- Attribute name cleanup ---------- */
    #"Replaced _ with space" =
        Table.ReplaceValue(Source, "_", " ", Replacer.ReplaceText, {"attribute_name"}),

    #"Replaced - with space" =
        Table.ReplaceValue(#"Replaced _ with space", "-", " ", Replacer.ReplaceText, {"attribute_name"}),

    #"Capitalized Each Word" =
        Table.TransformColumns(
            #"Replaced - with space",
            {{"attribute_name", Text.Proper, type text}}
        ),

    #"Fixed SKU" =
        Table.ReplaceValue(#"Capitalized Each Word", "Sku", "SKU", Replacer.ReplaceText, {"attribute_name"}),

    #"Fixed BA" =
        Table.ReplaceValue(#"Fixed SKU", "Ba", "BA", Replacer.ReplaceText, {"attribute_name"}),

    #"Null Attribute Name" =
        Table.ReplaceValue(#"Fixed BA", null, "(Blank)", Replacer.ReplaceValue, {"attribute_name"}),

    /* ---------- Pivot attributes ---------- */
    #"Pivoted Column" =
        Table.Pivot(
            #"Null Attribute Name",
            List.Distinct(#"Null Attribute Name"[attribute_name]),
            "attribute_name",
            "attribute_value"
        )
in
    #"Pivoted Column"
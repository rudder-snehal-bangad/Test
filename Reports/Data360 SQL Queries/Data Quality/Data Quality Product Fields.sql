let
    // Build full table reference dynamically
    FullTableName = 
        "`" & BillingProjectID & "." & DatasetName & ".products`",

    // Build dynamic SQL
    SQLStatement = 
		" with products_with_index AS (
			SELECT 
			distinct product.id,
			product.code as product_code,
			variant_name,
			product.template_name,
			product.category_name,
			product.brand_name,
			product.product_type,
			product.active,
			product.is_salable,
			product.is_gift_card,
			round(co.cost,2) as cost_price,
			row_number() over(partition by product.id order by product.code) as idx
			FROM " & FullTableName & "  product 
			left join unnest(costs) as co)
			select *,
			case when id is null then 0
			when idx =1 then 1
			else null
			end as product_order_data
			from products_with_index
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
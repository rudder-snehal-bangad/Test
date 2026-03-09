let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = BillingProject & "." & Dataset,
    Period = Number.ToText(#"Analysis Period (Years)"),
    SQLQuery ="
    WITH purchase_orders AS (
    SELECT
        po.id AS po_id,
        po.number AS po_number,
        line.product_code,
        line.quantity AS ordered_quantity,
        line.amount,
        po.requested_shipping_date,
        po.purchase_date,
        po.state as po_state
    FROM `" & BasePath & ".purchase_orders` AS po
    LEFT JOIN UNNEST(po.lines) AS line
),
supplier_shipments AS (
    SELECT
        ss.state,
        ss.id AS ss_id,
        ss.reference AS ss_reference,
        ss.effective_date,
        move.product_code,
        move.quantity AS ss_quantity,
        move.cost_price AS ss_amount,
        move.to_location_type,
        move.from_location_type,
        move.state as mov_state,
        ss.supplier_name
    FROM `" & BasePath & ".supplier_shipments` AS ss
    LEFT JOIN UNNEST(ss.moves) AS move
    WHERE from_location_type = 'supplier'
        AND to_location_type = 'storage'
),
po_ss_count AS (
    SELECT
        p.po_id,
        p.product_code
    FROM purchase_orders AS p
    LEFT JOIN supplier_shipments AS s ON p.product_code = s.product_code
)
SELECT DISTINCT
    p.po_number,
    s.ss_id,
    s.supplier_name,
    p.product_code,
    p.purchase_date,
    p.requested_shipping_date,
    p.ordered_quantity as po_quantity,
    s.effective_date as ss_effective_date,
    s.mov_state as state_mov,
    COALESCE(s.ss_quantity, 0) AS ss_quantity,
FROM purchase_orders AS p
LEFT JOIN supplier_shipments AS s ON p.product_code = s.product_code
LEFT JOIN po_ss_count AS c ON p.po_id = c.po_id AND p.product_code = c.product_code
WHERE s.ss_quantity IS NOT NULL 
and p.purchase_date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()"
	,
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
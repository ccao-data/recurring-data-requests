-- Script to gather all North Tri condo parcels from ccao.pin_condo_chars and
-- join on helpful columns for re-review by field. Worth noting this won't
-- include any condos not already in ccao.pin_condo_chars for the North Tri.
SELECT
    vpu.pin10,
    pcc.pin,
    vpu.lon,
    vpu.lat,
    CONCAT_WS(
        ' ',
        vpa.prop_address_full,
        vpa.prop_address_city_name || ', IL',
        vpa.prop_address_zipcode_1
    ) AS address,
    vpa.prop_address_unit_number AS unit,
    COUNT(*)
        OVER (PARTITION BY vpu.pin10)
        AS total_number_of_units_in_building,
    pcc.building_sf,
    CAST(NULL AS VARCHAR) AS new_building_sf,
    pcc.unit_sf,
    CAST(NULL AS VARCHAR) AS new_unit_sf,
    pcc.bedrooms,
    CAST(NULL AS VARCHAR) AS new_bedrooms,
    pcc.full_baths,
    CAST(NULL AS VARCHAR) AS new_full_baths,
    pcc.half_baths,
    CAST(NULL AS VARCHAR) AS new_half_baths,
    vpcr.is_parking_space AS parking_space,
    vpcr.parking_space_flag_reason,
    CAST(NULL AS VARCHAR) AS new_parking_space,
    vpu.township_name AS township,
    vpu.nbhd_code AS neighborhood_code,
    -- Aggregate all sales docs, dates, and prices per pin
    CASE WHEN
            vps2.doc_no IS NOT NULL THEN
        CONCAT(
            '[',
            vps2.doc_no,
            ', ',
            SUBSTR(CAST(vps2.sale_date AS VARCHAR), 1, 10),
            ', $',
            FORMAT('%,d', vps2.sale_price),
            ']'
        )
    END AS sales,
    -- Aggregate all permit numbers, dates, and work descriptions per pin
    CASE WHEN
            vpp.permit_number IS NOT NULL THEN
        CONCAT(
            '[',
            vpp.permit_number,
            ', ',
            SUBSTR(vpp.date_issued, 1, 10),
            ', ',
            vpp.work_description,
            ']'
        )
    END AS permits,
    vpcr.flag_comments AS "QC Flag"
FROM default.vw_pin_universe AS vpu
-- Ensure only condos that have been reviewed in the past are up for re-review
INNER JOIN ccao.pin_condo_char AS pcc
    ON vpu.pin = pcc.pin
INNER JOIN qc.vw_pin_condo_review AS vpcr
    ON vpu.pin = REPLACE(vpcr.pin, '-', '')
    AND vpu.year = vpcr.year
LEFT JOIN default.vw_pin_permit AS vpp
    ON vpu.pin = vpp.pin
    -- Limit permits to 2022 and after
    AND vpp.assessment_year >= '{min_year}'
LEFT JOIN default.vw_pin_sale AS vps2
    ON vpu.pin = vps2.pin
    -- Limit sales to 2022 and after
    AND vps2.year >= '{min_year}'
    AND vps2.is_outlier
LEFT JOIN default.vw_pin_address AS vpa
    ON vpu.pin = vpa.pin AND vpu.year = vpa.year
WHERE vpu.triad_name = '{tri}'
    AND vpu.year = (
        SELECT MAX(max_year.year) FROM default.vw_pin_universe AS max_year
    )

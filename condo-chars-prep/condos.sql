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
    vpu.township_name AS township,
    vpu.nbhd_code AS neighborhood_code,
    pcc.parking_pin,
    vps1.is_parking_space,
    vps1.parking_space_flag_reason,
    vps1.is_common_area,
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
    END AS permits
FROM default.vw_pin_universe AS vpu
-- Ensure only condos that have been reviewed in the past are up for re-review
INNER JOIN ccao.pin_condo_char AS pcc
    ON vpu.pin = pcc.pin
    AND vpu.year = pcc.year
LEFT JOIN default.vw_pin_permit AS vpp
    ON vpu.pin = vpp.pin
    -- Limit permits to 2022 and after
    AND vpp.assessment_year >= '{min_year}'
LEFT JOIN
    default.vw_pin_status AS vps1
    ON vpu.pin = vps1.pin
    AND vpu.year = vps1.year
LEFT JOIN default.vw_pin_sale AS vps2
    ON vpu.pin = vps2.pin
    -- Limit sales to 2022 and after
    AND vps2.year >= '{min_year}'
    AND vps2.sv_is_outlier
LEFT JOIN default.vw_pin_address AS vpa
    ON vpu.pin = vpa.pin AND vpu.year = vpa.year
WHERE vpu.triad_name = '{tri}'

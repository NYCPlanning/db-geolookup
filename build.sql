DROP SCHEMA IF EXISTS geo_lookups CASCADE;
CREATE SCHEMA geo_lookups;

-- Map population div lookup to standardized names, calculate centroid geom
SELECT 
        LEFT (a.bctcb2010, 1) as borocode,
        (CASE 
        	WHEN LEFT (a.bctcb2010, 1) = '1' THEN 'Manhattan'
        	WHEN LEFT (a.bctcb2010, 1) = '2' THEN 'Bronx'
        	WHEN LEFT (a.bctcb2010, 1) = '3' THEN 'Brooklyn'
        	WHEN LEFT (a.bctcb2010, 1) = '4' THEN 'Queens'
        	WHEN LEFT (a.bctcb2010, 1) = '5' THEN 'Staten Island'
        END) as boro,
        (CASE 
        	WHEN LEFT (a.bctcb2010, 1) = '1' THEN 'New York'
        	WHEN LEFT (a.bctcb2010, 1) = '2' THEN 'Bronx'
        	WHEN LEFT (a.bctcb2010, 1) = '3' THEN 'Kings'
        	WHEN LEFT (a.bctcb2010, 1) = '4' THEN 'Queens'
        	WHEN LEFT (a.bctcb2010, 1) = '5' THEN 'Richmond'
        END) as county,
        (CASE
                WHEN LEFT(a.bctcb2010, 1) = '1' THEN '36061'
                WHEN LEFT(a.bctcb2010, 1) = '2' THEN '36005'
                WHEN LEFT(a.bctcb2010, 1) = '3' THEN '36047'
                WHEN LEFT(a.bctcb2010, 1) = '4' THEN '36081'
                WHEN LEFT(a.bctcb2010, 1) = '5' THEN '36085'
        END) as county_fips, 
        RIGHT(a.bctcb2010, 10) as ctcb2010,
        SUBSTRING(a.bctcb2010, 2, 7) as ctcbg2010,
        RIGHT(a.bct2010, 6) as ct2010,
        nta,
        nta_name,
        puma,
        puma_name,
        puma_roughcd_equiv,
        cncld_2013 as councildst,
        cd as commntydst,
        ST_Centroid(b.wkb_geometry) as centroid_geom
        INTO geo_lookups.cd_bctcb2010_centroids
        FROM dcp_bctcb2010_cd_puma a
        JOIN dcp_censusblocks.latest b
        ON a.bctcb2010 = b.bctcb2010;
 
-- Combine FIRM and PFIRM records, excluding X zones       
SELECT *
	INTO geo_lookups.combined_floodzones
	FROM
	(SELECT 
		fld_zone, 
		wkb_geometry 
	FROM fema_pfirms2015_100yr.latest
	WHERE fld_zone <> 'X'
    UNION 
    SELECT 
    	fld_zone, 
    	wkb_geometry 
    FROM fema_firms2007_100yr.latest
    WHERE fld_zone <> 'X') a;

--  Create a single geometry for each floodplain
SELECT *
INTO geo_lookups.floodplain_geoms
FROM 
(SELECT 
	'500-year' as flood_type,
	ST_MakeValid(ST_Union(wkb_geometry)) as geom
FROM geo_lookups.combined_floodzones
UNION
SELECT
	'100-year' as flood_type,
	ST_MakeValid(ST_Union(wkb_geometry)) as geom
FROM geo_lookups.combined_floodzones
WHERE fld_zone <> '0.2 PCT ANNUAL CHANCE FLOOD HAZARD') b;
	
 
-- Compute 500-year floodplain flag   
SELECT 
	a.borocode,
	a.boro,
	a.county,
	a.county_fips,
	a.ctcb2010,
	a.ctcbg2010,
	a.ct2010,
	a.nta,
	a.nta_name,
	a.puma,
	a.puma_name,
	a.puma_roughcd_equiv,
	a.councildst,
	a.commntydst,
	st_intersects(a.centroid_geom, b.geom)::int as fp_500
INTO geo_lookups.in_500
FROM geo_lookups.cd_bctcb2010_centroids a, (
			SELECT geom as geom
			FROM geo_lookups.floodplain_geoms
			WHERE flood_type = '500-year'
			) b;

-- Compute 100-year floodplain flag  
SELECT 
	a.borocode,
	a.ctcb2010, 
	st_intersects(a.centroid_geom, b.geom)::int as fp_100
INTO geo_lookups.in_100
FROM geo_lookups.cd_bctcb2010_centroids a, (
	SELECT geom as geom
			FROM geo_lookups.floodplain_geoms
			WHERE flood_type = '100-year'
	) b;

-- Compute walk-to-park access zone flag
SELECT 
	a.borocode,
	a.ctcb2010, 
	st_intersects(a.centroid_geom, b.geom)::int as park_access
INTO geo_lookups.in_park_access
FROM cd_bctcb2010_centroids a, (
	SELECT st_union(wkb_geometry) as geom
	FROM  dpr_access_zone.latest
	) b;

-- Join flags into single lookup
WITH flood_join AS (
	SELECT a.*, b.fp_100
	FROM geo_lookups.in_500 a
	JOIN geo_lookups.in_100 b
	ON a.borocode||a.ctcb2010 = b.borocode||b.ctcb2010)
SELECT a.*, b.park_access
	INTO geo_lookups.geo_lookup
	FROM flood_join a
	JOIN geo_lookups.in_park_access b
	ON a.borocode||a.ctcb2010 = b.borocode||b.ctcb2010;
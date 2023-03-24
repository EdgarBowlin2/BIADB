set head off
set feedback off
set linesize 10000

SELECT
    JSON_OBJECT(
        'Type' IS b.target_type,
        'Name' IS b.target_name,
        'Severity' IS a.severity,
        'Message' IS a.summary_msg,
        'Date' IS to_char(a.last_updated_date, 'YYYY-MM-DD'),
        'Time' IS to_char(a.last_updated_date, 'HH24:MI:SS'),
        'Acknowledged' IS a.is_acknowledged
    )
FROM
    sysman.mgmt$incidents         a,
    sysman.mgmt$target            b,
    sysman.mgmt$incident_category c
WHERE
        a.target_guid = b.target_guid
    AND a.incident_id = c.incident_id
    AND b.target_type IN ( 'oracle_database', 'host', 'oracle_listener', 'has', 'osm_instance', 'oracle_emd' )
    AND c.category_name IN ( 'Availability', 'Capacity', 'Load' )
    AND a.open_status = '1'
    AND a.is_suppressed = '0'
    AND a.severity IN ( 'Warning', 'Critical', 'Fatal' )
ORDER BY
    a.last_updated_date DESC;

exit

# +------------------------------------------------------------------+
# |             ____ _               _        __  __ _  __           |
# |            / ___| |__   ___  ___| | __   |  \/  | |/ /           |
# |           | |   | '_ \ / _ \/ __| |/ /   | |\/| | ' /            |
# |           | |___| | | |  __/ (__|   <    | |  | | . \            |
# |            \____|_| |_|\___|\___|_|\_\___|_|  |_|_|\_\           |
# |                                                                  |
# | Copyright Mathias Kettner 2014             mk@mathias-kettner.de |
# +------------------------------------------------------------------+
#
# This file is part of Check_MK.
# The official homepage is at http://mathias-kettner.de/check_mk.
#
# check_mk is free software;  you can redistribute it and/or modify it
# under the  terms of the  GNU General Public License  as published by
# the Free Software Foundation in version 2.  check_mk is  distributed
# in the hope that it will be useful, but WITHOUT ANY WARRANTY;  with-
# out even the implied warranty of  MERCHANTABILITY  or  FITNESS FOR A
# PARTICULAR PURPOSE. See the  GNU General Public License for more de-
# tails. You should have  received  a copy of the  GNU  General Public
# License along with GNU Make; see the file  COPYING.  If  not,  write
# to the Free Software Foundation, Inc., 51 Franklin St,  Fifth Floor,
# Boston, MA 02110-1301 USA.
#
#
# Converted from bash to powershell
# Brian vd westhuizen
# 07/2017
# 
#
# create a check_mk user in postgres
#
# CREATE ROLE check_mk PASSWORD 'check_mk' SUPERUSER CREATEDB CREATEROLE INHERIT LOGIN;

################
# please set the psql location below
# and the username and password
# and update pg_hba.conf to allow this user to connect to postgres.
set-Location 'C:\PostgreSQL\9.6\bin\';
$env:PGPASSWORD = 'check_mk';
$U="check_mk"
$DB="postgres"
$PORT="5432"

$DATABASES = .\psql.exe -U $U -p $PORT -A -t -w -d postgres -c "SELECT datname FROM pg_database WHERE datistemplate = false;"

Echo "<<<postgres_sessions>>>"
$QNAME = & .\psql.exe -U $U -p $PORT -A -t -w -d ${DB} -c "select column_name from information_schema.columns where table_name='pg_stat_activity' and column_name in ('query','current_query');"
$OUTPUT = & .\psql.exe -U $U -p $PORT -A -t -w -d ${DB} -F" " -c "select $QNAME = '<IDLE>', count(*) from pg_stat_activity group by ($QNAME = '<IDLE>');"
$OUTPUT = $OUTPUT -replace '[|]'
Echo $OUTPUT
Echo "t 0"


Echo "<<<postgres_stat_database:sep(59)>>>"
$statsquery = "select datid, datname, numbackends, xact_commit, xact_rollback, blks_read, blks_hit, tup_returned, tup_fetched, tup_inserted, tup_updated, tup_deleted, pg_database_size(datname) as datsize 
from pg_stat_database;"

$stats = & .\psql.exe -U $U -p $PORT -A -F';' -d $DB -c $statsquery
echo $stats | foreach {$i=$null} {$i;$i=$_}
 
#Echo $stats

Echo "<<<postgres_locks:sep(59)>>>"
Echo "[databases_start]"
ForEach ($X in $DATABASES){
Echo $X
}
Echo "[databases_end]"

$LOCKS = & .\psql.exe -U $U -p $PORT -A -F';' -X -d ${DB} -c "SELECT datname, granted, mode FROM pg_locks l RIGHT JOIN pg_database d ON (d.oid=l.database) WHERE d.datallowconn;"
Echo "$LOCKS" | foreach {$i=$null} {$i;$i=$_}

# Querytime
Echo  "<<<postgres_query_duration:sep(59)>>>"
Echo "[databases_start]"
ForEach ($X in $DATABASES){
Echo $X
}
Echo "[databases_end]"

$QUERYTIME_QUERY = & .\psql.exe -U $U -p $PORT -X -A -F';' -d ${DB}  -c "SELECT datname, datid, usename, client_addr, state AS state, COALESCE(ROUND(EXTRACT(epoch FROM now()-query_start)),0) AS seconds,
 pid, regexp_replace(query, E'[\\n\\r\\u2028]+', ' ', 'g' ) AS current_query FROM pg_stat_activity WHERE (query_start IS NOT NULL AND (state NOT LIKE 'idle%' OR state IS NULL)) ORDER BY query_start, pid DESC;"
Echo $QUERYTIME_QUERY | foreach {$i=$null} {$i;$i=$_}
 
# Contains last vacuum time and analyze time
Echo '<<<postgres_stats:sep(59)>>>'
Echo "[databases_start]"
ForEach ($X in $DATABASES){
Echo $X
}
Echo "[databases_end]"
foreach ($X in $DATABASES){
    $LASTVACUUM = & .\psql.exe -U $U -p $PORT -X -d ${X} -A -F';' -c "BEGIN;
    SET statement_timeout=30000;
    COMMIT;
    SELECT current_database() AS datname, nspname AS sname, relname AS tname,
      CASE WHEN v IS NULL THEN -1 ELSE round(extract(epoch FROM v)) END AS vtime,
      CASE WHEN g IS NULL THEN -1 ELSE round(extract(epoch FROM g)) END AS atime
    FROM (SELECT nspname, relname, GREATEST(pg_stat_get_last_vacuum_time(c.oid),
          pg_stat_get_last_autovacuum_time(c.oid)) AS v,
          GREATEST(pg_stat_get_last_analyze_time(c.oid), pg_stat_get_last_autoanalyze_time(c.oid)) AS g
          FROM pg_class c, pg_namespace n
          WHERE relkind = 'r'
          AND n.oid = c.relnamespace
          AND n.nspname <> 'information_schema'
          ORDER BY 3) AS foo;"
    Echo $LASTVACUUM | foreach {$i=$null} {$i;$i=$_}
}
    
Echo '<<<postgres_version:sep(1)>>>'
$vers = .\psql.exe -U $U -p $PORT -d ${DB} -X -t -A -F';' -c "SELECT version() AS v"
Echo $vers


# Number of current connections per database
Echo '<<<postgres_connections:sep(59)>>>'
# We need to output the databases, too.
# This query does not report databases without an active query
Echo "[databases_start]"
ForEach ($X in $DATABASES){
Echo $X
}
Echo "[databases_end]"

$CONNECTIONS = & .\psql.exe -U $U -p $PORT -X -d ${DB} -A -F';' -c "SELECT COUNT(datid) AS current,
  (SELECT setting AS mc FROM pg_settings WHERE name = 'max_connections') AS mc,
  d.datname
FROM pg_database d
LEFT JOIN pg_stat_activity s ON (s.datid = d.oid) WHERE state <> 'idle'
GROUP BY 2,3
ORDER BY datname;"
Echo $CONNECTIONS | foreach {$i=$null} {$i;$i=$_}

# Bloat index and tables
Echo "<<<postgres_bloat:sep(59)>>>"
Echo "[databases_start]"
ForEach ($X in $DATABASES){
Echo $X
}
Echo "[databases_end]"

$BLOAT_QUERY="SELECT current_database() AS db, schemaname, tablename, reltuples::bigint AS tups, relpages::bigint AS pages, otta,
  ROUND(CASE WHEN otta=0 OR sml.relpages=0 OR sml.relpages=otta THEN 0.0 ELSE sml.relpages/otta::numeric END,1) AS tbloat,
  CASE WHEN relpages < otta THEN 0 ELSE relpages::bigint - otta END AS wastedpages,
  CASE WHEN relpages < otta THEN 0 ELSE bs*(sml.relpages-otta)::bigint END AS wastedbytes,
  CASE WHEN relpages < otta THEN 0 ELSE (bs*(relpages-otta))::bigint END AS wastedsize,
  iname, ituples::bigint AS itups, ipages::bigint AS ipages, iotta,
   ROUND(CASE WHEN iotta=0 OR ipages=0 OR ipages=iotta THEN 0.0 ELSE ipages/iotta::numeric END,1) AS ibloat,
   CASE WHEN ipages < iotta THEN 0 ELSE ipages::bigint - iotta END AS wastedipages,
   CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta) END AS wastedibytes,
   CASE WHEN ipages < iotta THEN 0 ELSE (bs*(ipages-iotta))::bigint END AS wastedisize,
   CASE WHEN relpages < otta THEN
     CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta::bigint) END
     ELSE CASE WHEN ipages < iotta THEN bs*(relpages-otta::bigint)
       ELSE bs*(relpages-otta::bigint + ipages-iotta::bigint) END
   END AS totalwastedbytes
 FROM (
   SELECT
     nn.nspname AS schemaname,
     cc.relname AS tablename,
     COALESCE(cc.reltuples,0) AS reltuples,
     COALESCE(cc.relpages,0) AS relpages,
     COALESCE(bs,0) AS bs,
     COALESCE(CEIL((cc.reltuples*((datahdr+ma-
       (CASE WHEN datahdr%ma=0 THEN ma ELSE datahdr%ma END))+nullhdr2+4))/(bs-20::float)),0) AS otta,
     COALESCE(c2.relname,'?') AS iname, COALESCE(c2.reltuples,0) AS ituples, COALESCE(c2.relpages,0) AS ipages,
     COALESCE(CEIL((c2.reltuples*(datahdr-12))/(bs-20::float)),0) AS iotta -- very rough approximation, assumes all cols
   FROM
      pg_class cc
   JOIN pg_namespace nn ON cc.relnamespace = nn.oid AND nn.nspname <> 'information_schema'
   LEFT JOIN
   (
     SELECT
       ma,bs,foo.nspname,foo.relname,
       (datawidth+(hdr+ma-(case when hdr%ma=0 THEN ma ELSE hdr%ma END)))::numeric AS datahdr,
       (maxfracsum*(nullhdr+ma-(case when nullhdr%ma=0 THEN ma ELSE nullhdr%ma END))) AS nullhdr2
     FROM (
       SELECT
         ns.nspname, tbl.relname, hdr, ma, bs,
         SUM((1-coalesce(null_frac,0))*coalesce(avg_width, 2048)) AS datawidth,
         MAX(coalesce(null_frac,0)) AS maxfracsum,
         hdr+(
           SELECT 1+count(*)/8
           FROM pg_stats s2
           WHERE null_frac<>0 AND s2.schemaname = ns.nspname AND s2.tablename = tbl.relname
         ) AS nullhdr
       FROM pg_attribute att
       JOIN pg_class tbl ON att.attrelid = tbl.oid
       JOIN pg_namespace ns ON ns.oid = tbl.relnamespace
       LEFT JOIN pg_stats s ON s.schemaname=ns.nspname
       AND s.tablename = tbl.relname
       AND s.inherited=false
       AND s.attname=att.attname,
       (
         SELECT
           (SELECT current_setting('block_size')::numeric) AS bs,
             CASE WHEN SUBSTRING(SPLIT_PART(v, ' ', 2) FROM '#\[0-9]+.[0-9]+#\%' for '#')
               IN ('8.0','8.1','8.2') THEN 27 ELSE 23 END AS hdr,
           CASE WHEN v ~ 'mingw32' OR v ~ '64-bit' THEN 8 ELSE 4 END AS ma
         FROM (SELECT version() AS v) AS foo
       ) AS constants
       WHERE att.attnum > 0 AND tbl.relkind='r'
       GROUP BY 1,2,3,4,5
     ) AS foo
   ) AS rs
   ON cc.relname = rs.relname AND nn.nspname = rs.nspname
   LEFT JOIN pg_index i ON indrelid = cc.oid
   LEFT JOIN pg_class c2 ON c2.oid = i.indexrelid
 ) AS sml
  WHERE sml.relpages - otta > 0 OR ipages - iotta > 10 ORDER BY totalwastedbytes DESC LIMIT 10;"

  foreach ($X in $DATABASES){
 
     $RESPONSE = &.\psql.exe -U $U -p $PORT -X -d ${X} -A -F';' -c $BLOAT_QUERY 
     
     Echo $RESPONSE | foreach {$i=$null} {$i;$i=$_}
 }
 
 

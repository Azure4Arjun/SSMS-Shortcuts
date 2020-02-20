/* 5 - 2020-02-20 DB Info
Consolidated by Slava Murygin
http://slavasql.blogspot.com/2016/02/ssms-query-shortcuts.html */

IF CAST(CAST(SERVERPROPERTY('ProductVersion') as CHAR(2)) as NUMERIC) < 10
BEGIN
SELECT @@VERSION
RAISERROR ('To run this script SQL Server has to be Version 2008 or higher.',16,1)
END
GO
IF(SERVERPROPERTY('collation')!=DATABASEPROPERTYEX(DB_name(),'collation'))
BEGIN
USE tempdb;
RAISERROR ('Because of database collation is not equal to the "master" context has been switched to "tempdb".',16,1)
END
GO
IF OBJECT_ID('tempdb..#tbl_DB_Statistics') IS NOT NULL
DROP TABLE #tbl_DB_Statistics;
GO
IF OBJECT_ID('tempdb..#tbl_VLFInfo') IS NOT NULL
DROP TABLE #tbl_VLFInfo;
GO
IF OBJECT_ID('tempdb..#tbl_VLFCountResults') IS NOT NULL
DROP TABLE #tbl_VLFCountResults;
GO
IF OBJECT_ID('tempdb..#tbl_AG_DBs') IS NOT NULL
DROP TABLE #tbl_AG_DBs;
GO
IF OBJECT_ID('tempdb..#USP_GETDB') IS NOT NULL
DROP PROCEDURE #USP_GETDB;
GO
IF OBJECT_ID('tempdb..#tbl_DB_CPU%') IS NOT NULL
DROP TABLE [#tbl_DB_CPU%];
GO
CREATE TABLE #tbl_DB_Statistics(
database_id INT,
[File Id] INT,
SizeMB VARCHAR(16),
MaxSizeMB VARCHAR(16),
UsedSpaceMB VARCHAR(16),
FreeSpacePrc CHAR(6),
[File Group] VARCHAR(128),
UsedSpace FLOAT
);
GO
CREATE TABLE #tbl_VLFInfo (
RecoveryUnitID INT,
FileID INT,
FileSize BIGINT,
StartOffset BIGINT,
FSeqNo BIGINT,
[Status] BIGINT,
Parity BIGINT,
CreateLSN NUMERIC(38));
GO
CREATE TABLE #tbl_AG_DBs (
[DB_Name] SYSNAME NULL,
database_id INT,
[AG Name] SYSNAME,
[Role] NVARCHAR(60),
Node NVARCHAR(256),
Position VARCHAR(5),
is_local BIT,
[Status] NVARCHAR(60),
operational_Status TINYINT,
[State] NVARCHAR(60),
[Join State] NVARCHAR(60),
[Recovery Status] NVARCHAR(60),
recovery_health TINYINT,
[Replica Sync Health] NVARCHAR(60),
synchronization_health TINYINT,
[Group Sync Health] NVARCHAR(60),
[Group Health] NVARCHAR(60),
[Last Error] NVARCHAR(1024),
[Last Error #] VARCHAR(10),
[Last Error DT] CHAR(23),
sync_state NVARCHAR(60),
synchronization_state TINYINT,
[Commit participant] VARCHAR(3),
[DB State] NVARCHAR(60),
Suspended VARCHAR(3),
[Suspend Reason] NVARCHAR(60),
replica_server_name NVARCHAR(256),
[Replica Owner] NVARCHAR(128),
availability_mode_desc NVARCHAR(60),
failover_mode_desc NVARCHAR(60),
session_timeout INT,
[Is Readable] NVARCHAR(60),
create_date  CHAR(23),
modify_date  CHAR(23),
[backup_priority] INT,
[endpoint_url] NVARCHAR(256),
read_only_routing_url NVARCHAR(256),
[Listener DNS Name] NVARCHAR(63),
[Listener Port] INT,
ip_configuration_string_from_cluster NVARCHAR(4000),
[Current Listener State] NVARCHAR(max),
recovery_lsn NUMERIC(25,0),
truncation_lsn NUMERIC(25,0),
last_sent_lsn NUMERIC(25,0),
last_sent_time DATETIME,
last_received_lsn NUMERIC(25,0),
last_received_time DATETIME,
last_hardened_lsn NUMERIC(25,0),
last_hardened_time DATETIME,
last_redone_lsn NUMERIC(25,0),
last_redone_time DATETIME,
log_send_queue_size BIGINT,
log_send_rate BIGINT,
redo_queue_size BIGINT,
redo_rate BIGINT,
filestream_send_rate BIGINT,
end_of_log_lsn NUMERIC(25,0),
last_commit_lsn NUMERIC(25,0),
last_commit_time DATETIME);
GO
CREATE TABLE #tbl_VLFCountResults([DB_id] INT, VLFCount INT);
GO
CREATE TABLE [#tbl_DB_CPU%](DatabaseID INT,[CPU Percent] CHAR(8));
GO
CREATE PROCEDURE #USP_GETDB @Param SYSNAME = NULL WITH RECOMPILE AS
SET NOCOUNT ON

PRINT 'Function Ctrl-5 Options: SQL Server Database Details.';
PRINT '1. No options Returns List of all Databases with following info:
	- Databases: ID, Name, State, User Access, Recovery Model, Compatibility Level, Collation, etc.
	- Files: ID, Name, Type, State, Physical Name, Size (Mb), Used Space (Mb), Free Space (%),
	  Auto Growth, Average Read/Write waits (Ms), CPU Usage by DB, Number of VLFs per Log File;
	Additional DataSet with:
	- List of Volumes used by SQL Server data and log files;
	- Average Read/Write waits (Ms) per Volume;
	- Total space per Volume;
	- Free space with percentage per Volume;
	If Availability Group is present returns general information about the group
	and participating SQL Server Instances.
	- List of SQL Server Logins;';
PRINT '2. Database Name or ID Returns:
	- Only one DB will be shown;
	- List of Partition Schemas with Partitions and ranges;
	- List of all DB Settings;
	- List of Database Users/Roles;
	- Database Backup History.';
PRINT '3. Extra parameters (Assuming there are no Databases with one charachter name):
	N - Sorts Databases by Name;
	D - Sorts Databases by Creation Date/Time;
	S - Sorts Database files by Size (Desc);
	U - Sorts Database files by Usage percentage (Desc);
	W - Sorts Database files by Write/Read Waits (Desc);
	C - Filters Databases, which are not in Current compatability mode;
	B - Filters Databases, which are in BULK recovery model;
	F - Filters Databases, which are in FULL recovery model;
	L - Filters Databases, which are in SIMPLE recovery model;
	M - Filters Databases, which are not in MULTI_USER mode;
	O - Filters Databases, which are not ONLINE;
	R - Filters Databases, which are in Read-Only Mode;
	A - List Availability groups with Databases;';
PRINT '4. Availability Group name: AG Info.'

DECLARE @S CHAR(80), @V INT; --SQL Server Major Version
DECLARE @SQL NVARCHAR(MAX), @SQL1 NVARCHAR(MAX), @SQL2 NVARCHAR(MAX);
DECLARE @ag_present INT, @nl NVARCHAR(MAX), @or NCHAR(18), @ny NCHAR(50), @oo NCHAR(36);
DECLARE @P NCHAR(1), @CompLevel INT, @DBid INT;

SELECT @V=CAST(CAST(SERVERPROPERTY('ProductVersion') as CHAR(2)) as NUMERIC)
	, @S=REPLICATE('-',80), @ag_present = 0, @nl = ' with (NOLOCK) '
	, @CompLevel=compatibility_level, @P  = NULL
	, @or='OPTION (RECOMPILE)'
	, @ny=' WHEN 0 THEN ''NO'' WHEN 1 THEN ''YES'' ELSE ''N/A'' END'
	, @oo=' WHEN 0 THEN ''OFF'' ELSE ''ON'' END'
	, @DBid=CASE WHEN @Param is Null THEN 0
		WHEN DB_ID(@Param) Is Null THEN -1 ELSE DB_ID(@Param) END
FROM sys.databases WHERE database_id = 1;

TRUNCATE TABLE #tbl_AG_DBs;
TRUNCATE TABLE #tbl_DB_Statistics;
TRUNCATE TABLE #tbl_VLFInfo;
TRUNCATE TABLE #tbl_VLFCountResults;

PRINT @S;
IF LEN(@Param)=1 and @DBid=-1
BEGIN
	SELECT @P = UPPER(LEFT(@Param,1)), @Param = Null;
END

/* Collect Availability Groups information */
IF @V >= 11
BEGIN
	SET @SQL = '
INSERT INTO #tbl_AG_DBs
SELECT DB_NAME(database_id)
, s.database_id
, g.name
, IsNull(st.role_desc, CASE WHEN r.replica_server_name = gs.primary_replica THEN ''PRIMARY'' ELSE ''SECONDARY'' END)
, n.node_name
, CASE s.is_local WHEN 1 THEN ''LOCAL'' ELSE '''' END
, s.is_local
, IsNull(st.operational_state_desc, '''')
, st.operational_state
, IsNull(st.connected_state_desc,'''')
, IsNull(cs.join_state_desc,'''')
, IsNull(st.recovery_health_desc,'''')
, IsNull(st.recovery_health,'''')
, IsNull(st.synchronization_health_desc,'''')
, st.synchronization_health
, gs.synchronization_health_desc
, ISNull(gs.primary_recovery_health_desc, gs.secondary_recovery_health_desc)
, IsNull(st.last_connect_error_description,'''')
, IsNull(CAST(st.last_connect_error_number as VARCHAR),'''')
, IsNull(CONVERT(VARCHAR(23),st.last_connect_error_timestamp,121),'''')
, IsNull(s.synchronization_state_desc,'''')
, s.synchronization_state
, CASE s.is_commit_participant'+@ny+'
, IsNull(s.database_state_desc,'''')
, CASE s.is_suspended'+@ny+'
, IsNull(s.suspend_reason_desc,'''')
, IsNull(r.replica_server_name,'''')
, [Replica Owner] = IsNull(suser_sname(r.owner_sid),'''')
, r.availability_mode_desc
, r.failover_mode_desc
, r.session_timeout
, CASE st.role WHEN 1
	THEN r.primary_role_allow_connections_desc
	ELSE r.secondary_role_allow_connections_desc END
, IsNull(CONVERT(VARCHAR(23),r.create_date,121),'''')
, IsNull(CONVERT(VARCHAR(23),r.modify_date,121),'''')
, r.backup_priority
, r.endpoint_url
, IsNull(r.read_only_routing_url,'''')
, l.dns_name
, l.port
, l.ip_configuration_string_from_cluster
, agip.agip
, s.recovery_lsn, s.truncation_lsn, s.last_sent_lsn, s.last_sent_time, s.last_received_lsn
, s.last_received_time, s.last_hardened_lsn, s.last_hardened_time, s.last_redone_lsn
, s.last_redone_time, s.log_send_queue_size, s.log_send_rate, s.redo_queue_size, s.redo_rate
, s.filestream_send_rate, s.end_of_log_lsn, s.last_commit_lsn, s.last_commit_time
FROM sys.availability_groups as g'+@nl+'
INNER HASH JOIN sys.availability_replicas as r'+@nl+'
	ON g.group_id = r.group_id
LEFT JOIN sys.dm_hadr_database_replica_states as s'+@nl+'
	ON s.group_id = g.group_id and s.replica_id = r.replica_id
LEFT JOIN sys.dm_hadr_availability_replica_cluster_nodes as n'+@nl+'
	ON r.replica_server_name = n.replica_server_name and g.name = n.group_name
LEFT JOIN sys.dm_hadr_availability_replica_states as st'+@nl+'
	ON s.replica_id = st.replica_id and s.group_id = st.group_id
LEFT JOIN sys.dm_hadr_availability_replica_cluster_states as cs'+@nl+'
	ON s.group_id = cs.group_id and cs.replica_id = s.replica_id
LEFT JOIN sys.availability_group_listeners as l'+@nl+'
	ON l.group_id = g.group_id
CROSS APPLY (
	SELECT TOP 100 PERCENT state_desc + '': '' + ip_address + '';''
		+ ip_subnet_mask + ''/'' + CAST(network_subnet_prefix_length as VARCHAR)
		+ CAST(CASE is_dhcp WHEN 1 THEN '';DHCP'' ELSE '''' END + '';'' as VARCHAR(5))
	FROM sys.availability_group_listener_ip_addresses as ip'+@nl+'
	WHERE l.listener_id = ip.listener_id
	ORDER BY listener_id, state DESC
	FOR XML PATH('''')
) as agip(agip)
LEFT JOIN sys.dm_hadr_availability_group_states as gs'+@nl+'
	ON gs.group_id = g.group_id
WHERE ' + CAST(@DBid as VARCHAR) + ' < 1 OR	s.database_id = ' + CAST(@DBid as VARCHAR) + '
/*
-- Uncomment if you have Administrator''s permissions
OPTION (QUERYTRACEON 9481, RECOMPILE)
*/
;';
	PRINT @SQL
	RAISERROR (@S,10,1) WITH NOWAIT
	EXEC (@SQL);

	IF EXISTS ( SELECT TOP 1 1 FROM #tbl_AG_DBs) SET @ag_present = 1;
END

IF @ag_present = 1 and @DBid = -1 and @V >= 11 /*Double If to prevent error in SQL2008*/
IF (EXISTS (SELECT TOP 1 1 FROM sys.availability_groups WHERE name = @Param) OR ASCII(@P) = 65)
BEGIN
	/* Return info for individual AG*/
	SET @SQL = 'SELECT [Node], [AG Name], replica_server_name, [Replica Owner], [DB_Name]
, last_commit_time, Position, is_local, [Status], [State], [Join State]
, availability_mode_desc, failover_mode_desc
, session_timeout, [Is Readable], create_date, modify_date, backup_priority
, [Recovery Status], [Replica Sync Health], [Last Error #], [Last Error DT]
, [Commit participant], [DB State], Suspended, [Suspend Reason]
, endpoint_url, [Listener DNS Name], [Listener Port]
, ip_configuration_string_from_cluster, [Current Listener State]
, read_only_routing_url, recovery_lsn, truncation_lsn, last_sent_lsn, last_sent_time
, last_received_lsn, last_received_time, last_hardened_lsn, last_hardened_time
, last_redone_lsn, last_redone_time, end_of_log_lsn, last_commit_lsn
, log_send_queue_size, log_send_rate, redo_queue_size, redo_rate, filestream_send_rate
FROM #tbl_AG_DBs ' + CASE ASCII(@P) WHEN 65 THEN '' ELSE 'WHERE [AG Name] = '''+@Param+'''' END + '
ORDER BY replica_server_name, [DB_Name]
'+@or;
	PRINT @SQL;
	PRINT @S;
	EXEC (@SQL);
	RETURN;
END

DECLARE @i INT = (
SELECT CASE WHEN @DBid > 0 THEN @DBid
ELSE (
	SELECT Min(d.database_id) FROM sys.databases as d
	LEFT JOIN master.sys.database_recovery_status as s
		ON d.database_id = s.database_id
	WHERE @P is Null
		OR @P IN ('N','D','S','U','W')
		OR (@P = 'F' and d.recovery_model = 1)
		OR (@P = 'B' and d.recovery_model = 2)
		OR (@P = 'L' and d.recovery_model = 3)
		OR (@P = 'O' and d.[state] != 0)
		OR (@P = 'C' and d.[compatibility_level] != @CompLevel)
		OR (@P = 'M' and d.user_access != 0)
		OR (@P = 'R' and d.is_read_only != 0)
		OR (@P = 'E' and d.recovery_model = 1 and s.last_log_backup_lsn is Null)
) END
);

WHILE @i Is not Null
IF @DBid<=0 OR @i=@DBid
BEGIN
	SELECT @SQL2 = '
INSERT INTO #tbl_DB_Statistics (database_id, [File Id], SizeMB, UsedSpaceMB, FreeSpacePrc, UsedSpace)
SELECT
	Database_Id=DB_ID(''' + DB_NAME(@i) + '''),
	[File Id]=Null,
	SizeMB=Null,
	UsedSpaceMB=''UNKNOWN'',
	FreeSpacePrc=''0'',0
	'+@or+';';

	SELECT @SQL = CASE [state] + user_access WHEN 0
	THEN 'USE [' + DB_NAME(@i) + '];
WITH DbData as (
SELECT Database_Id=DB_ID(''' + DB_NAME(@i) + ''')
	,[File Id]=f.file_id
	,[Physical Name]=f.physical_name
	,SizeMB=CAST(CAST(ROUND(f.Size/128.,3) as DECIMAL(16,3)) as VARCHAR(16))
	,MaxSizeMB=CASE f.max_size WHEN 0 THEN ''NO GROWTH'' WHEN -1 THEN ''2097152.000'' ELSE CAST(CAST(ROUND(f.max_size/128.,3) as DECIMAL(16,3)) as VARCHAR(16)) END
	,UsedSpaceMB=CAST(CAST(ROUND(FILEPROPERTY(f.name, ''SpaceUsed'')/128.,3) as DECIMAL(16,3)) as VARCHAR(16))
	,FreeSpacePrc=RIGHT(''  '' + CAST(CAST((1 - FILEPROPERTY(f.name, ''SpaceUsed'') * 1./ f.size) * 100 as DECIMAL(5,2)) as VARCHAR(6)),6)
	,[File Group]=CASE f.file_id WHEN 2 THEN ''Log File'' ELSE IsNull(g.name,''N/A'') END
	,UsedSpace=FILEPROPERTY(f.name, ''SpaceUsed'') * 1./ f.size
FROM sys.database_files as f'+@nl+'
LEFT JOIN sys.filegroups as g'+@nl+'ON f.data_space_id = g.data_space_id
)
INSERT INTO #tbl_DB_Statistics
SELECT Database_Id, [File Id]
	,SizeMB=RIGHT(SPACE(16) + CASE WHEN Len(SizeMB) > 7
		THEN CASE WHEN Len(SizeMB) > 10
		THEN LEFT(SizeMB, LEN(SizeMB) - 10) + '','' + SUBSTRING(SizeMB, LEN(SizeMB) - 10, 3) + '','' + RIGHT(SizeMB, 7)
		ELSE LEFT(SizeMB, LEN(SizeMB) - 7) + '','' + RIGHT(SizeMB, 7) END ELSE SizeMB END, 16)
	,MaxSizeMB=RIGHT(SPACE(16) + CASE WHEN Len(MaxSizeMB) > 7
		THEN CASE WHEN Len(MaxSizeMB) > 10
		THEN LEFT(MaxSizeMB, LEN(MaxSizeMB) - 10) + '','' + SUBSTRING(MaxSizeMB, LEN(MaxSizeMB) - 10, 3) + '','' + RIGHT(MaxSizeMB, 7)
		ELSE LEFT(MaxSizeMB, LEN(MaxSizeMB) - 7) + '','' + RIGHT(MaxSizeMB, 7) END ELSE MaxSizeMB END, 16)
	,UsedSpaceMB=RIGHT(SPACE(16) + CASE WHEN Len(UsedSpaceMB) > 7
		THEN CASE WHEN Len(UsedSpaceMB) > 10
		THEN LEFT(UsedSpaceMB, LEN(UsedSpaceMB) - 10) + '','' + SUBSTRING(UsedSpaceMB, LEN(UsedSpaceMB) - 10, 3) + '','' + RIGHT(UsedSpaceMB, 7)
		ELSE LEFT(UsedSpaceMB, LEN(UsedSpaceMB) - 7) + '','' + RIGHT(UsedSpaceMB, 7) END ELSE UsedSpaceMB END, 16)
		,FreeSpacePrc
		,[File Group]
		,UsedSpace
FROM DbData
'+@or
	ELSE
		@SQL2
	END
	FROM sys.databases with (nolock)
	WHERE database_id = @i;

	SELECT @SQL1 = CASE [state] + user_access WHEN 0
	THEN 'USE [' + DB_NAME(@i) + '];
INSERT INTO #tbl_VLFInfo(' + CASE WHEN @V < 11 THEN '' ELSE 'RecoveryUnitID, ' END + 'FileID, FileSize, StartOffset, FSeqNo, [Status], Parity, CreateLSN)
EXEC sp_executesql N''DBCC LOGINFO() WITH NO_INFOMSGS'';
				
INSERT INTO #tbl_VLFCountResults
SELECT DB_ID(), COUNT(*)
FROM #tbl_VLFInfo;

TRUNCATE TABLE #tbl_VLFInfo;'
	ELSE '' END FROM sys.databases with (nolock) WHERE database_id = @i;
	
	PRINT @SQL
	PRINT @SQL1
	RAISERROR (@S,10,1) WITH NOWAIT
	
	BEGIN TRY
		EXEC (@SQL);
	END TRY
	BEGIN CATCH
		
		RAISERROR (@S,10,1) WITH NOWAIT
		PRINT 'Error in script execution. Executing different script:'
		RAISERROR (@S,10,1) WITH NOWAIT
		PRINT @SQL2
		RAISERROR (@S,10,1) WITH NOWAIT
		EXEC (@SQL2);
	END CATCH

	BEGIN TRY
		EXEC (@SQL1);
	END TRY
	BEGIN CATCH
		PRINT 'Error accessing DBCC LOGINFO().'
	END CATCH

	SELECT @i = Min(d.database_id)
	FROM sys.databases as d with (nolock)
		LEFT JOIN master.sys.database_recovery_status as s with (nolock)
			ON d.database_id = s.database_id
		WHERE d.database_id > @i AND (
			@P is Null
			OR @P IN ('N','D','S','U','W')
			OR (@P = 'F' and d.recovery_model = 1)
			OR (@P = 'B' and d.recovery_model = 2)
			OR (@P = 'L' and d.recovery_model = 3)
			OR (@P = 'O' and d.[state] != 0)
			OR (@P = 'C' and d.[compatibility_level] != @CompLevel)
			OR (@P = 'M' and d.user_access != 0)
			OR (@P = 'E' and d.recovery_model = 1 and s.last_log_backup_lsn is Null)
		)
END
ELSE /* IF doing single DB we do a skip */
BEGIN
	SELECT @i = Min(database_id)
	FROM sys.databases with (nolock)
	WHERE database_id > @i;
END

SET @SQL='INSERT INTO [#tbl_DB_CPU%]
SELECT DatabaseID, CAST(CAST(SUM(total_worker_time)*100./(SELECT SUM(total_worker_time) FROM sys.dm_exec_query_stats with (NOLOCK) ) as DECIMAL(5,2)) as VARCHAR)+'' %''
FROM sys.dm_exec_query_stats AS qs with (NOLOCK)
CROSS APPLY (SELECT CONVERT(int, value) AS [DatabaseID]
FROM sys.dm_exec_plan_attributes(qs.plan_handle)
WHERE attribute = N''dbid'') AS F_DB
GROUP BY DatabaseID
HAVING SUM(total_worker_time) > (SELECT SUM(total_worker_time) FROM sys.dm_exec_query_stats with (NOLOCK) ) / 100'
+@or

PRINT SUBSTRING(@SQL,1,4000)
PRINT SUBSTRING(@SQL,4001,8000)
RAISERROR (@S,10,1) WITH NOWAIT
EXEC (@SQL);


SET @SQL=';WITH Counters as (
	SELECT d.database_id, c.cntr_value, c.counter_name
	, File_Id = CASE WHEN RTRIM(c.counter_name) in (
	''Log Bytes Flushed/sec'',''Log Flush Wait Time'',
	''Log Flush Waits/sec'',''Log Flush Write Time (ms)'',
	''Log Flushes/sec'',''Log Pool Cache Misses/sec'',
	''Log Pool Disk Reads/sec'',''Log Pool Requests/sec'',
	''Log Truncations'') THEN 2 ELSE 1 END
	FROM sys.dm_os_performance_counters as c'+@nl+'
	INNER JOIN sys.databases as d'+@nl+'ON name = RTRIM(instance_name)
	WHERE RTRIM(SUBSTRING(object_name, PATINDEX(''%:%'', object_name)+1, 99))
		not in (''Availability Replica'',''Broker Activation'',''HTTP Storage''
		,''Locks'',''SQL Errors'',''Broker Activation'',''Cursor Manager by Type''
		,''Database Mirroring'',''Plan Cache'')
), Perf_Counters as (
SELECT * FROM Counters
pivot (SUM (cntr_value) for counter_name in (
[Cache Hit Ratio Base],[Cache Hit Ratio],[Active Transactions],
[Log Bytes Flushed/sec],[Log Flush Wait Time],[Log Flush Waits/sec],
[Log Flush Write Time (ms)],[Log Flushes/sec],[Log Pool Cache Misses/sec],
[Log Pool Disk Reads/sec],[Log Pool Requests/sec],[Log Truncations],
[Backup/Restore Throughput/sec],[Bulk Copy Rows/sec],[Bulk Copy Throughput/sec],
[Cache Entries Count],[Cache Entries Pinned Count],[DBCC Logical Scan Bytes/sec],
'+CASE @ag_present WHEN 0 THEN ''
ELSE '[Mirrored Write Transactions/sec],[Log Bytes Received/sec],[Redone Bytes/sec],
[Transaction Delay],' END+'[Transactions/sec],[Write Transactions/sec]
)) as AvgIncomePerDay)
SELECT [Database ID]=t.database_id
,[Database State]=d.state_desc
,[Database Name]=d.name
,t.[File Group]
,[File Id]=mf.[file_id]
,[File Name]=mf.name
,[Physical Name]=mf.physical_name
,[File Type]=mf.type_desc
,[VLF Count]=IsNull(CASE WHEN mf.type_desc = ''LOG'' THEN CAST(v.VLFCount as VARCHAR)
	WHEN t.database_id = 2 THEN ''Org.Size: '' + CAST(mf.size/128 as VARCHAR) + ''Mb''
	ELSE '''' END,-1)
,[File Size, MB]=IsNull(t.SizeMB, CASE WHEN mf.size/128. > = 1000000 THEN CAST(mf.size/128000000 as VARCHAR) + '','' ELSE '''' END
+ RIGHT(CASE WHEN mf.size >= 128000000 THEN ''000'' ELSE '''' END + CASE WHEN mf.size/128. > = 1000 THEN CAST(((mf.size/128) % 1000000) / 1000 as VARCHAR) + '','' ELSE '''' END ,4)
+ RIGHT(CASE WHEN mf.size >= 128000 THEN ''000'' ELSE '''' END + CASE WHEN mf.size/128. > 0 THEN CAST(((mf.size/128) % 1000) as VARCHAR) END,3)
+ ''.'' + SUBSTRING(CAST( ROUND(mf.size/128. - mf.size/128,1) as VARCHAR),3,1))
,[Used Space, MB]=IsNull(t.UsedSpaceMB,''N/A'')
,[Free Space]=IsNull(t.FreeSpacePrc + '' %'',''N/A'')
,AutoGrowth=CASE is_percent_growth WHEN 0 THEN CAST(growth/128 as VARCHAR) + '' Mb''
		ELSE CAST(growth as VARCHAR) + '' %'' END
,[Max File Size, MB]=t.MaxSizeMB
,[Avg Read Wait, ms]=CAST(ROUND(( s.io_stall_read_ms / ( 1.0 + s.num_of_reads ) ),3) as FLOAT)
,[Avg Write Wait, ms]=CAST(ROUND(( s.io_stall_write_ms / ( 1.0 + s.num_of_writes ) ),3) as FLOAT)
,[CPU Percent]=IsNull(dbs.[CPU Percent],'''')
,[Created]=CONVERT(CHAR(19),d.create_date,121)
,[File State]=mf.state_desc
,[Log Reuse Wait]=d.log_reuse_wait_desc
,[User Access]=d.user_access_desc
,[Recovery Model]=d.recovery_model_desc
,[Last Full Backup]=CASE d.database_id WHEN 2 THEN ''N/A'' ELSE
CASE WHEN lbu.Last_BU is Null THEN '+
CASE @ag_present WHEN 0 THEN '''Unknown''' ELSE '
CASE a.role WHEN ''Secondary'' THEN ''Secondary AG'' ELSE ''Unknown'' END' END + '
ELSE lbu.Last_BU END END
,[Backup Chain]=CASE d.recovery_model WHEN 1 THEN
	CASE WHEN r.last_log_backup_lsn is Null THEN ''Broken'' ELSE ''Good'' END	ELSE ''N/A'' END
,[Compatibility Level]=[compatibility_level]
,[Auto Create Stats]=CASE d.is_auto_create_stats_on'+@ny+'
,[Auto Update Stats]=CASE d.is_auto_update_stats_on'+@ny+'
,[Auto Close]=CASE d.is_auto_close_on'+@ny+'
,[Auto Shrink]=CASE d.is_auto_shrink_on'+@ny+'
,[Snapshot Isolation]=d.snapshot_isolation_state_desc
,[Collation Name]=d.collation_name
,[Page Verify Option]=d.page_verify_option_desc
,[Access State]=CASE d.is_read_only WHEN 0 THEN ''READ_WRITE'' ELSE ''READ_ONLY'' END
, CASE d.is_in_standby WHEN 0 THEN ''Active'' ELSE ''Standby for Log Restore'' END as [Mode] '+
CASE @ag_present WHEN 0 THEN '' ELSE '
,[Availability Group]=IsNull(a.[AG Name],''N/A'')
,[AG Synchronization Health]=IsNull(a.[Sync Health],''N/A'')
,[AG Synchronization State]=IsNull(a.sync_state,''N/A'')
,[AG State]=IsNull(a.[DB State],''N/A'')
,[Role]=IsNull(a.Role,''N/A'')
,[Is Readable]=IsNull(a.[Is Readable],''N/A'')
' END+
',pc.*
FROM #tbl_DB_Statistics as t
INNER JOIN master.sys.databases as d'+@nl+'
	ON t.database_id = d.database_id ' +
	CASE @ag_present WHEN 0 THEN '' ELSE '
LEFT JOIN (
SELECT DISTINCT a.database_id, a.[AG Name]
, [Health] = (SELECT CASE MIN(synchronization_health)
	WHEN 0 THEN ''NOT HEALTHY'' WHEN 1 THEN ''PARTIALLY HEALTHY''
	WHEN 2 THEN ''HEALTHY'' END FROM #tbl_AG_DBs as i
	WHERE i.database_id = a.database_id GROUP BY i.database_id)
, [Sync Health] = ( /*Logic to retranslate 3->(-2), 4->(-1)*/
	SELECT CASE MIN(synchronization_state-(synchronization_state/3)*5)
	WHEN 0 THEN ''NOT SYNCHRONIZING''	WHEN 1 THEN ''SYNCHRONIZING''
	WHEN 2 THEN ''SYNCHRONIZED'' WHEN -1 THEN ''INITIALIZING''
	WHEN -2 THEN ''REVERTING'' END FROM #tbl_AG_DBs as i
	WHERE i.database_id = a.database_id GROUP BY i.database_id)
, [DB State]
, [Role]
, [Is Readable]
, sync_state
FROM #tbl_AG_DBs as a WHERE is_local = 1) as a
	ON t.database_id = a.database_id' END + '
LEFT JOIN sys.master_files AS mf'+@nl+'
	ON d.database_id = mf.database_id AND (t.[File Id] = mf.[file_id] or t.[File Id] is Null)
LEFT JOIN (
	SELECT database_name, Last_BU=CONVERT(CHAR(19),MAX(backup_finish_date),121)
	FROM msdb.dbo.backupset'+@nl+' WHERE type = ''D'' GROUP BY database_name
) as lbu ON d.name = lbu.database_name
LEFT JOIN master.sys.database_recovery_status as r '+@nl+'ON r.database_id = d.database_id
LEFT JOIN Perf_Counters as pc ON pc.database_id = d.database_id and pc.[file_id] = mf.[file_id]
LEFT JOIN sys.dm_io_virtual_file_stats(NULL, NULL) as s
	ON t.database_id = s.database_id and mf.[file_id] = s.[file_id]
LEFT JOIN #tbl_VLFCountResults as v ON v.[DB_id] = d.database_id
LEFT JOIN [#tbl_DB_CPU%] as dbs ON dbs.DatabaseID = d.database_id
';
	SET @SQL += ' ORDER BY ' + CASE @P
		WHEN 'N' THEN 'd.name'
		WHEN 'D' THEN 'd.create_date'
		WHEN 'S' THEN 'mf.size DESC'
		WHEN 'U' THEN 't.UsedSpace DESC'
		WHEN 'W' THEN 's.io_stall_read_ms / ( 1.0 + s.num_of_reads ) + s.io_stall_write_ms / ( 1.0 + s.num_of_writes ) DESC'
		ELSE 'd.Database_id'
	END

	SET @SQL += ' '+@or+';';

	PRINT SUBSTRING(@SQL,1,4000)
	PRINT SUBSTRING(@SQL,4001,8000)
	RAISERROR (@S,10,1) WITH NOWAIT
	EXEC (@SQL);

IF @V >= 11
BEGIN
SET @SQL = 'SELECT [Mount Point]=vs.volume_mount_point
,[Avg Read Wait, ms]=CAST(ROUND(( SUM(s.io_stall_read_ms) / ( 1.0 + SUM(s.num_of_reads) ) ),3) as FLOAT)
,[Avg Write Wait, ms]=CAST(ROUND(( SUM(s.io_stall_write_ms) / ( 1.0 + SUM(s.num_of_writes) ) ),3) as FLOAT)
,[Total Volume Size (GB)]=CONVERT(DECIMAL(18,2),vs.total_bytes/1073741824.0)
,[Available Volume Size (GB)]=CONVERT(DECIMAL(18,2),vs.available_bytes/1073741824.0)
,[Volume Space Free %]=CAST(CAST(vs.available_bytes AS FLOAT)/ CAST(vs.total_bytes AS FLOAT) AS DECIMAL(18,2)) * 100
,vs.file_system_type,vs.logical_volume_name
FROM sys.dm_io_virtual_file_stats(NULL, NULL) as s
CROSS APPLY sys.dm_os_volume_stats(s.database_id, s.[file_id]) AS vs
GROUP BY vs.volume_mount_point, vs.file_system_type, vs.logical_volume_name, vs.total_bytes, vs.available_bytes
'+@or+';';

	PRINT @SQL
	RAISERROR (@S,10,1) WITH NOWAIT
	EXEC (@SQL);
END

IF @ag_present > 0
BEGIN
	SET @SQL = 'SELECT [AG Name]
,Replicas=COUNT(DISTINCT replica_server_name)
,Databases=COUNT(DISTINCT database_id)
,[Group Health], [Group Sync Health]
,[Listener DNS Name], [Listener Port], ip_configuration_string_from_cluster
,[Current Listener State]
FROM #tbl_AG_DBs
GROUP BY [AG Name], [Group Health], [Group Sync Health]
, [Listener DNS Name], [Listener Port], ip_configuration_string_from_cluster
, [Current Listener State]
ORDER BY [AG Name] '+@or+';';
	PRINT @SQL
	RAISERROR (@S,10,1) WITH NOWAIT
	EXEC (@SQL);
END

IF @DBid = 0
BEGIN
	/* Extract List of SQL Server Logins */
	SET @SQL = 'SELECT [Login/User Name]=IsNull(l.name,pr.Name)
,[Login/User Type]=pr.type_desc
,pr.default_database_name
,[Assigned Roles]=IsNull(SUBSTRING((
	SELECT '', '' + p.name  FROM master.sys.server_role_members as rm
	INNER JOIN master.sys.server_principals as p
		ON rm.role_principal_id = p.principal_id and p.type = ''R''
	WHERE rm.member_principal_id = pr.principal_id
	FOR XML PATH('''')
),3,8000),''NO ROLE ASSIGNED'')
,[Special Permissions]=IsNull(SUBSTRING((
	SELECT '', '' + permission_name + ''('' + ip.name + '')''
	FROM master.sys.server_permissions as sp
	INNER JOIN master.sys.server_principals as ip ON ip.principal_id = sp.grantor_principal_id
	WHERE sp.grantee_principal_id = pr.principal_id
	FOR XML PATH('''')
),3,8000),''N/A'')
,is_disabled=IsNull(CAST(pr.is_disabled as varchar),''N/A'')
,is_policy_checked=IsNull(CAST(l.is_policy_checked as varchar),''N/A'')
,is_expiration_checked=IsNull(CAST(l.is_expiration_checked as varchar),''N/A'')
,[Password Problem]=CASE
	WHEN PWDCOMPARE(l.name,l.password_hash) = 1 THEN ''Login With Password Same AS Name''
	WHEN PWDCOMPARE('''',l.password_hash) = 1 THEN ''Login With Empty Password''
	ELSE ''No Problem Found''
END
FROM master.sys.sql_logins as l
RIGHT JOIN master.sys.server_principals as pr ON l.principal_id = pr.principal_id
WHERE pr.type in (''S'',''U'',''G'') '+@or+';'

	PRINT @SQL
	RAISERROR (@S,10,1) WITH NOWAIT
	EXEC (@SQL);
END

IF @DBid > 0
BEGIN
	/* Extract List of Partition Schemas if any */
	SET @SQL='
USE ['+@Param+'];
IF EXISTS (SELECT TOP 1 1 FROM sys.partition_schemes'+@nl+')
SELECT ps.name as Partition_Schema, pf.name as Partition_Function
, pf.modify_date as Last_Modified
, CASE pf.boundary_value_on_right WHEN 0 THEN ''LEFT'' ELSE ''RIGHT'' END as Function_Type
, R1.value as Min_Border_Value, R2.value as Max_Border_Value
, ds.destination_id as Partition_Order
, FG.name as [FileGroup_Name]
,total_pages=SUM(IsNull(AU.total_pages,0))
,used_pages=SUM(IsNull(AU.used_pages,0))
,data_pages=SUM(IsNull(AU.data_pages,0))
,[File_Name]=sf.name
,Physical_File_Name=sf.filename
FROM sys.partition_schemes as ps'+@nl+'
INNER JOIN sys.destination_data_spaces as ds'+@nl+'ON ps.data_space_id = ds.partition_scheme_id
INNER JOIN sys.partition_functions as pf'+@nl+'ON pf.function_id = ps.function_id
INNER JOIN sys.filegroups AS FG'+@nl+'ON FG.data_space_id = ds.data_space_id
INNER JOIN sys.sysfiles AS sf'+@nl+'ON sf.groupid = ds.data_space_id
LEFT JOIN sys.partition_range_values as R1'+@nl+'ON R1.function_id = pf.function_id and R1.boundary_id + 1 = ds.destination_id
LEFT JOIN sys.partition_range_values as R2'+@nl+'ON R2.function_id = pf.function_id and R2.boundary_id = ds.destination_id
LEFT JOIN sys.allocation_units AS AU'+@nl+'ON AU.data_space_id = ds.data_space_id
GROUP BY  ps.name, pf.name, pf.modify_date, pf.boundary_value_on_right, R1.value, R2.value
	, ds.destination_id, FG.name, sf.name, sf.filename
ORDER BY ps.name, ds.destination_id
'+@or+';';

	PRINT @SQL
	RAISERROR (@S,10,1) WITH NOWAIT
	EXEC (@SQL);

	/* Extract individual database parameters */
	SET @SQL = 'SELECT tt.DBProperty, tt.DBPropertyValue
FROM sys.databases as t'+@nl+'
CROSS APPLY (VALUES (CAST(database_id as NVARCHAR), ''Database Id'')
,(name, ''Datanase Name'')
,(state_desc COLLATE SQL_Latin1_General_CP1_CI_AS, ''DB State'')
,(user_access_desc COLLATE SQL_Latin1_General_CP1_CI_AS, ''User Access'')
,(recovery_model_desc COLLATE SQL_Latin1_General_CP1_CI_AS, ''DB recovery model'')
,(collation_name COLLATE SQL_Latin1_General_CP1_CI_AS, ''DB Collation'')
,(log_reuse_wait_desc COLLATE SQL_Latin1_General_CP1_CI_AS, ''Log Reuse'')
,(page_verify_option_desc COLLATE SQL_Latin1_General_CP1_CI_AS, ''PAGE_VERIFY'')
,(CASE is_read_only'+@ny+', ''READ_ONLY'')
,(CASE is_in_standby'+@ny+', ''DB IN Standby'')
,(CASE is_cleanly_shutdown'+@ny+', ''DB Is cleanly shutdown'')
,(CASE is_encrypted'+@ny+', ''DB_ENCRYPTED'')
,(CASE is_auto_shrink_on'+@ny+', ''AUTO_SHRINK'')
,(CASE is_ansi_null_default_on'+@oo+', ''ANSI_NULL_DEFAULT'')
,(CASE is_ansi_nulls_on'+@oo+', ''ANSI_NULLS'')
,(CASE is_ansi_warnings_on'+@oo+', ''ANSI_WARNINGS'')
,(CASE is_ansi_padding_on'+@oo+', ''ANSI_PADDING'')
,(CASE is_arithabort_on'+@oo+', ''Arithmetic Abort Enabled'')
,(CASE is_quoted_identifier_on'+@oo+', ''QUOTED_IDENTIFIER'')
,(CASE is_auto_create_stats_on'+@oo+', ''AUTO_CREATE_STATISTICS'')
,(CASE is_auto_update_stats_on'+@oo+', ''AUTO_UPDATE_STATISTICS'')
,(CASE is_auto_update_stats_async_on'+@oo+', ''AUTO_UPDATE_STATISTICS_ASYNC'')
,(CASE is_read_committed_snapshot_on'+@oo+', ''READ_COMMITTED_SNAPSHOT'')
,(CASE snapshot_isolation_state'+@ny+', ''ALLOW_SNAPSHOT_ISOLATION'')
,(CASE is_concat_null_yields_null_on'+@oo+', ''CONCAT_NULL_YIELDS_NULL'')
,(CASE is_recursive_triggers_on'+@oo+', ''RECURSIVE_TRIGGERS'')
,(CASE is_parameterization_forced'+@ny+', ''FORCED_PARAMETRIZATION'')
,(CASE is_db_chaining_on'+@oo+', ''DB_CHAINING'')
,(CASE is_numeric_roundabort_on'+@oo+', ''NUMERIC_ROUNDABORT'')
,(CASE is_trustworthy_on'+@oo+', ''TRUSTWORTHY'')
,(CASE is_auto_close_on'+@oo+', ''AUTO_CLOSE'')
,(CASE is_date_correlation_on'+@oo+', ''DATE_CORRELATION_OPTIMIZATION'')
,(CASE is_cdc_enabled'+@ny+', ''CHANGE_DATA_CAPTURE Enabled'')
,(CASE is_fulltext_enabled'+@ny+', ''FULL-TEXT Enabled'')
,(CASE is_supplemental_logging_enabled'+@ny+', ''SUPPLEMENTAL_LOGGING Enabled'')
,(CASE is_broker_enabled'+@ny+', ''DB_BROKER Enabled'')
,(CASE is_honor_broker_priority_on'+@oo+', ''HONOR_BROKER_PRIORITY'')
,(CASE is_local_cursor_default'+@ny+', ''CURSOR_DEFAULT'')
,(CASE is_cursor_close_on_commit_on'+@oo+', ''CURSOR_CLOSE_ON_COMMIT'')
,(CASE is_subscribed'+@ny+', ''REPLICATION_SUBSCRIPTION_DB'')
,(CASE is_published'+@ny+', ''REPLICATION_PUBLICATION_DB'')
,(CASE is_merge_published'+@ny+', ''MERGE_REPLICATION_PUBLICATION_DB'')
,(CASE is_distributor'+@ny+', ''REPLICATION_DISTRIBUTION_DB'')
,(CASE is_sync_with_backup'+@ny+', ''MARKED_FOR_REPLICATION_BACKUP_SYNC'')
,(CASE is_master_key_encrypted_by_server'+@ny+', ''DB_ENCRYPTED_MASTER_KEY'')
) tt (DBPropertyValue, DBProperty)
WHERE name = '''+@Param+'''
'+@or+';';

	PRINT @SQL
	RAISERROR (@S,10,1) WITH NOWAIT
	EXEC (@SQL);

	/* Extract database Users */
	SET @SQL = '
SELECT [User Name]=d.name
,[Login Name]=IsNull(p.name,''N/A'')
,d.type_desc
,[Assigned Roles]=IsNull(SUBSTRING((
	SELECT '', '' + dr.name
	FROM ['+@Param+'].sys.database_principals as dr
	INNER JOIN ['+@Param+'].sys.database_role_members as m
		ON dr.principal_id = m.role_principal_id
	WHERE d.principal_id = m.member_principal_id
	FOR XML PATH('''')
),3,8000),''N/A''),d.create_date,d.modify_date
FROM ['+@Param+'].sys.database_principals as d
LEFT JOIN master.sys.server_principals as p ON p.sid = d.sid
WHERE d.is_fixed_role = 0 and d.principal_id > 4
'+@or+';';

	PRINT @SQL
	RAISERROR (@S,10,1) WITH NOWAIT
	EXEC (@SQL);

	/* Extract database backup History */
	SET @SQL = '
	;WITH BU as (SELECT backup_start_date, backup_finish_date,
	[Type]=CASE type
		WHEN ''L'' THEN ''LOG''
		WHEN ''D'' THEN ''FULL''
		WHEN ''I'' THEN ''DIFF''
		ELSE ''N/A'' END
	,BMb=CAST(CAST(ROUND(backup_size / 1048576.,3) as DECIMAL(16,3)) as VARCHAR(16))
	,CMb=CAST(CAST(ROUND(compressed_backup_size / 1048576.,3) as DECIMAL(16,3)) as VARCHAR(16))
	,[Backup File Full Name]=f.physical_device_name, backup_set_id
	FROM msdb.dbo.backupset as s
	LEFT JOIN msdb.dbo.backupmediafamily as f ON s.media_set_id = f.media_set_id
	WHERE database_name = '''+@Param+'''
	)
	SELECT backup_start_date, backup_finish_date, [Type], [Backup File Full Name]
	,BackupSizeMb=RIGHT(SPACE(16) + CASE WHEN Len(BMb) > 7
		THEN CASE WHEN Len(BMb) > 10
		THEN LEFT(BMb, LEN(BMb) - 10) + '','' + SUBSTRING(BMb, LEN(BMb) - 10, 3) + '','' + RIGHT(BMb, 7)
				ELSE LEFT(BMb, LEN(BMb) - 7) + '','' + RIGHT(BMb, 7) END ELSE BMb END, 16)
	,CompressedMb=RIGHT(SPACE(16) + CASE WHEN Len(CMb) > 7
		THEN CASE WHEN Len(CMb) > 10
		THEN LEFT(CMb, LEN(CMb) - 10) + '','' + SUBSTRING(CMb, LEN(CMb) - 10, 3) + '','' + RIGHT(CMb, 7)
				ELSE LEFT(CMb, LEN(CMb) - 7) + '','' + RIGHT(CMb, 7) END ELSE CMb END, 16)
	FROM BU
	ORDER BY backup_set_id DESC
	'+@or+';';

	PRINT @SQL
	RAISERROR (@S,10,1) WITH NOWAIT
	EXEC (@SQL);

END

RETURN 0;
GO
EXEC #USP_GETDB 
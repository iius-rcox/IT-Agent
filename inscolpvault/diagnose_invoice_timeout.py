"""
Invoice Timeout Diagnostic Script for pVault
Specifically diagnoses the LoadInvoicesByStatusID timeout issue
"""

import pyodbc
import sys
from datetime import datetime

# Connection parameters
SERVER = "inscolpvault.insulationsinc.local"
PORT = 55859
DATABASE = "PaperlessEnvironments"

def connect_to_sql(username, password):
    """Establish SQL Server connection"""
    drivers = ["ODBC Driver 18 for SQL Server", "ODBC Driver 17 for SQL Server"]

    for driver in drivers:
        try:
            connection_string = (
                f"DRIVER={{{driver}}};"
                f"SERVER={SERVER},{PORT};"
                f"DATABASE={DATABASE};"
                f"UID={username};"
                f"PWD={password};"
                f"TrustServerCertificate=yes;"
                f"Encrypt=yes;"
            )
            conn = pyodbc.connect(connection_string, timeout=30)
            print(f"✓ Connected using {driver}")
            return conn
        except:
            continue

    print("✗ Failed to connect")
    sys.exit(1)

def diagnose_invoice_tables(conn):
    """Analyze invoice-related tables"""
    print("\n" + "="*60)
    print("INVOICE TABLE ANALYSIS")
    print("="*60)

    cursor = conn.cursor()

    # Find invoice-related tables
    print("\n[1. Invoice-Related Tables]")
    cursor.execute("""
    SELECT
        s.name AS SchemaName,
        t.name AS TableName,
        p.rows AS RowCnt,
        SUM(a.total_pages) * 8 / 1024.0 AS SizeMB
    FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN sys.indexes i ON t.object_id = i.object_id
    INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
    INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
    WHERE t.name LIKE '%invoice%' OR t.name LIKE '%status%'
    GROUP BY s.name, t.name, p.rows
    ORDER BY p.rows DESC
    """)

    invoice_tables = cursor.fetchall()
    if invoice_tables:
        for table in invoice_tables:
            print(f"\n{table.SchemaName}.{table.TableName}")
            print(f"  Rows: {table.RowCnt:,}")
            print(f"  Size: {table.SizeMB:.2f} MB")
            if table.RowCnt > 1000000:
                print("  ⚠ WARNING: Large table - needs proper indexing!")

def check_invoice_indexes(conn):
    """Check indexes on invoice-related tables"""
    print("\n" + "="*60)
    print("INVOICE TABLE INDEXES")
    print("="*60)

    cursor = conn.cursor()

    # Check existing indexes
    print("\n[2. Existing Indexes on Invoice Tables]")
    cursor.execute("""
    SELECT
        t.name AS TableName,
        i.name AS IndexName,
        i.type_desc AS IndexType,
        STUFF((
            SELECT ', ' + c.name
            FROM sys.index_columns ic
            INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
            WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id
            ORDER BY ic.key_ordinal
            FOR XML PATH('')
        ), 1, 2, '') AS IndexColumns,
        ps.avg_fragmentation_in_percent AS Fragmentation,
        i.is_disabled AS IsDisabled
    FROM sys.tables t
    INNER JOIN sys.indexes i ON t.object_id = i.object_id
    LEFT JOIN sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ps
        ON i.object_id = ps.object_id AND i.index_id = ps.index_id
    WHERE (t.name LIKE '%invoice%' OR t.name LIKE '%status%')
        AND i.name IS NOT NULL
    ORDER BY t.name, i.index_id
    """)

    indexes = cursor.fetchall()
    if indexes:
        current_table = ""
        for idx in indexes:
            if idx.TableName != current_table:
                print(f"\n{idx.TableName}:")
                current_table = idx.TableName

            print(f"  • {idx.IndexName} ({idx.IndexType})")
            print(f"    Columns: {idx.IndexColumns}")
            if idx.Fragmentation and idx.Fragmentation > 30:
                print(f"    ⚠ FRAGMENTED: {idx.Fragmentation:.1f}%")
            if idx.IsDisabled:
                print(f"    ⚠ DISABLED INDEX!")

def check_missing_invoice_indexes(conn):
    """Check for missing indexes on invoice queries"""
    print("\n" + "="*60)
    print("MISSING INDEXES FOR INVOICE QUERIES")
    print("="*60)

    cursor = conn.cursor()

    print("\n[3. Recommended Missing Indexes]")
    cursor.execute("""
    SELECT TOP 10
        CONVERT(decimal(18,2), user_seeks * avg_total_user_cost * (avg_user_impact * 0.01)) AS IndexAdvantage,
        mid.statement AS TableName,
        mid.equality_columns AS EqualityColumns,
        mid.inequality_columns AS InequalityColumns,
        mid.included_columns AS IncludedColumns,
        migs.user_seeks AS UserSeeks,
        migs.avg_user_impact AS AvgUserImpact,
        'CREATE INDEX IX_' + REPLACE(REPLACE(REPLACE(
            OBJECT_NAME(mid.object_id), '[', ''), ']', ''), ' ', '_') + '_' +
            CAST(mig.index_group_handle AS VARCHAR(10)) +
            ' ON ' + mid.statement + ' (' +
            ISNULL(mid.equality_columns, '') +
            CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL
                THEN ',' ELSE '' END +
            ISNULL(mid.inequality_columns, '') + ')' +
            CASE WHEN mid.included_columns IS NOT NULL
                THEN ' INCLUDE (' + mid.included_columns + ')' ELSE '' END AS CreateStatement
    FROM sys.dm_db_missing_index_group_stats AS migs
    INNER JOIN sys.dm_db_missing_index_groups AS mig
        ON migs.group_handle = mig.index_group_handle
    INNER JOIN sys.dm_db_missing_index_details AS mid
        ON mig.index_handle = mid.index_handle
    WHERE mid.database_id = DB_ID()
        AND (mid.statement LIKE '%invoice%' OR mid.statement LIKE '%status%')
    ORDER BY IndexAdvantage DESC
    """)

    missing = cursor.fetchall()
    if missing:
        print("\n⚠ CRITICAL: Missing indexes detected for invoice tables!")
        for idx in missing:
            print(f"\nTable: {idx.TableName}")
            print(f"Impact Score: {idx.IndexAdvantage:.2f}")
            print(f"User Seeks: {idx.UserSeeks:,}")
            print(f"Performance Impact: {idx.AvgUserImpact:.1f}%")
            print(f"\nRECOMMENDED INDEX:")
            print(f"{idx.CreateStatement}")
            print("-" * 40)
    else:
        print("\n✓ No missing indexes detected for invoice tables")

def analyze_invoice_queries(conn):
    """Analyze recent invoice query performance"""
    print("\n" + "="*60)
    print("INVOICE QUERY PERFORMANCE ANALYSIS")
    print("="*60)

    cursor = conn.cursor()

    # Check query plan cache for invoice queries
    print("\n[4. Recent Invoice Query Performance]")
    cursor.execute("""
    SELECT TOP 10
        qs.execution_count,
        qs.total_elapsed_time / 1000000 AS TotalElapsedSec,
        qs.total_elapsed_time / qs.execution_count / 1000000.0 AS AvgElapsedSec,
        qs.max_elapsed_time / 1000000.0 AS MaxElapsedSec,
        qs.total_logical_reads / qs.execution_count AS AvgLogicalReads,
        qs.total_worker_time / 1000000.0 AS TotalCPUSec,
        SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
            ((CASE qs.statement_end_offset
                WHEN -1 THEN DATALENGTH(st.text)
                ELSE qs.statement_end_offset
            END - qs.statement_start_offset)/2) + 1) AS QueryText
    FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
    WHERE st.text LIKE '%invoice%' OR st.text LIKE '%status%'
    ORDER BY qs.total_elapsed_time DESC
    """)

    queries = cursor.fetchall()
    if queries:
        for i, q in enumerate(queries[:5], 1):
            print(f"\n[Query {i}]")
            print(f"Executions: {q.execution_count:,}")
            print(f"Avg Time: {q.AvgElapsedSec:.2f}s")
            print(f"Max Time: {q.MaxElapsedSec:.2f}s")
            print(f"Avg Reads: {q.AvgLogicalReads:,}")

            if q.AvgElapsedSec > 20:
                print("⚠ CRITICAL: Average execution time exceeds 20 seconds!")
            elif q.AvgElapsedSec > 10:
                print("⚠ WARNING: Slow query performance")

            if q.MaxElapsedSec > 30:
                print("⚠ TIMEOUT RISK: Max execution time exceeds 30 seconds!")

            print(f"Query: {str(q.QueryText)[:200]}...")

def check_invoice_statistics(conn):
    """Check statistics on invoice tables"""
    print("\n" + "="*60)
    print("INVOICE TABLE STATISTICS")
    print("="*60)

    cursor = conn.cursor()

    print("\n[5. Statistics Status]")
    cursor.execute("""
    SELECT
        OBJECT_NAME(s.object_id) AS TableName,
        s.name AS StatisticName,
        sp.last_updated,
        DATEDIFF(day, sp.last_updated, GETDATE()) AS DaysOld,
        sp.rows,
        sp.modification_counter AS ModificationsSinceUpdate,
        CASE
            WHEN sp.modification_counter > sp.rows * 0.2 THEN 'CRITICAL'
            WHEN sp.modification_counter > sp.rows * 0.1 THEN 'WARNING'
            WHEN DATEDIFF(day, sp.last_updated, GETDATE()) > 30 THEN 'STALE'
            ELSE 'OK'
        END AS Status
    FROM sys.stats s
    CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
    WHERE OBJECT_NAME(s.object_id) LIKE '%invoice%' OR OBJECT_NAME(s.object_id) LIKE '%status%'
    ORDER BY sp.modification_counter DESC
    """)

    stats = cursor.fetchall()
    if stats:
        for s in stats:
            if s.Status != 'OK':
                print(f"\n{s.TableName}.{s.StatisticName}")
                print(f"  Last Updated: {s.last_updated} ({s.DaysOld} days ago)")
                print(f"  Rows: {s.rows:,}")
                print(f"  Modifications: {s.ModificationsSinceUpdate:,}")
                print(f"  Status: {s.Status}")

                if s.Status == 'CRITICAL':
                    print("  ⚠ CRITICAL: Update statistics immediately!")

def check_current_invoice_queries(conn):
    """Check currently running invoice queries"""
    print("\n" + "="*60)
    print("CURRENTLY EXECUTING INVOICE QUERIES")
    print("="*60)

    cursor = conn.cursor()

    cursor.execute("""
    SELECT
        r.session_id,
        r.status,
        r.command,
        r.total_elapsed_time / 1000 AS ElapsedSec,
        r.wait_type,
        r.blocking_session_id,
        t.text AS QueryText,
        DB_NAME(r.database_id) AS DatabaseName
    FROM sys.dm_exec_requests r
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
    WHERE r.session_id > 50
        AND (t.text LIKE '%invoice%' OR t.text LIKE '%status%')
    ORDER BY r.total_elapsed_time DESC
    """)

    current = cursor.fetchall()
    if current:
        print("\n⚠ Active invoice queries detected:")
        for q in current:
            print(f"\nSession {q.session_id}")
            print(f"  Status: {q.status}")
            print(f"  Elapsed: {q.ElapsedSec}s")
            if q.blocking_session_id:
                print(f"  ⚠ BLOCKED BY SESSION {q.blocking_session_id}")
            if q.wait_type:
                print(f"  Waiting on: {q.wait_type}")
            print(f"  Query: {str(q.QueryText)[:150]}...")
    else:
        print("\n✓ No active invoice queries")

def generate_fix_script(conn):
    """Generate SQL scripts to fix issues"""
    print("\n" + "="*60)
    print("RECOMMENDED FIX SCRIPTS")
    print("="*60)

    print("\n[Quick Fix Scripts]")
    print("\n-- 1. Update all statistics on invoice tables")
    print("UPDATE STATISTICS [dbo].[YourInvoiceTableName] WITH FULLSCAN;")

    print("\n-- 2. Rebuild fragmented indexes")
    print("ALTER INDEX ALL ON [dbo].[YourInvoiceTableName] REBUILD;")

    print("\n-- 3. Clear plan cache for invoice queries (forces new plans)")
    print("DBCC FREEPROCCACHE;")

    print("\n-- 4. Set query timeout in application (C# example)")
    print("// In your data access layer:")
    print("command.CommandTimeout = 60; // 60 seconds instead of default 30")

def main():
    print("="*60)
    print("PVAULT INVOICE TIMEOUT DIAGNOSTIC")
    print("="*60)
    print(f"Server: {SERVER}:{PORT}")
    print(f"Database: {DATABASE}")
    print(f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    username = input("\nSQL Username: ")
    password = input("SQL Password: ")

    try:
        conn = connect_to_sql(username, password)

        # Run all diagnostics
        diagnose_invoice_tables(conn)
        check_invoice_indexes(conn)
        check_missing_invoice_indexes(conn)
        analyze_invoice_queries(conn)
        check_invoice_statistics(conn)
        check_current_invoice_queries(conn)
        generate_fix_script(conn)

        print("\n" + "="*60)
        print("DIAGNOSTIC SUMMARY")
        print("="*60)
        print("\n[Action Items]")
        print("1. Create any recommended missing indexes")
        print("2. Update statistics on invoice tables")
        print("3. Rebuild fragmented indexes")
        print("4. Consider increasing query timeout in application")
        print("5. Review and optimize slow queries identified above")

        conn.close()

    except Exception as e:
        print(f"\n✗ Error: {str(e)}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()
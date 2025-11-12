"""
Real-time Query Performance Monitor for pVault
Continuously monitors and logs query performance to identify timeout patterns
"""

import pyodbc
import time
import csv
from datetime import datetime
import os
import sys

# Configuration
SERVER = "inscolpvault.insulationsinc.local"
PORT = 55859
DATABASE = "PaperlessEnvironments"
MONITOR_INTERVAL = 5  # Check every 5 seconds
LOG_FILE = f"query_performance_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"

class QueryMonitor:
    def __init__(self, username, password):
        self.username = username
        self.password = password
        self.connection = None
        self.csv_writer = None
        self.csv_file = None
        self.alert_threshold = 20  # Alert for queries > 20 seconds

    def connect(self):
        """Establish database connection"""
        drivers = ["ODBC Driver 18 for SQL Server", "ODBC Driver 17 for SQL Server"]

        for driver in drivers:
            try:
                connection_string = (
                    f"DRIVER={{{driver}}};"
                    f"SERVER={SERVER},{PORT};"
                    f"DATABASE={DATABASE};"
                    f"UID={self.username};"
                    f"PWD={self.password};"
                    f"TrustServerCertificate=yes;"
                    f"Encrypt=yes;"
                )
                self.connection = pyodbc.connect(connection_string, timeout=10)
                print(f"✓ Connected using {driver}")
                return True
            except:
                continue

        print("✗ Failed to connect")
        return False

    def setup_logging(self):
        """Initialize CSV logging"""
        self.csv_file = open(LOG_FILE, 'w', newline='')
        self.csv_writer = csv.writer(self.csv_file)
        self.csv_writer.writerow([
            'Timestamp', 'SessionID', 'Status', 'Command', 'ElapsedSec',
            'WaitType', 'BlockingSession', 'Database', 'QuerySnippet', 'Alert'
        ])
        print(f"✓ Logging to {LOG_FILE}")

    def monitor_queries(self):
        """Monitor currently executing queries"""
        cursor = self.connection.cursor()

        query = """
        SELECT
            r.session_id,
            r.status,
            r.command,
            r.total_elapsed_time / 1000.0 AS ElapsedSec,
            r.wait_type,
            r.blocking_session_id,
            r.cpu_time / 1000.0 AS CPUSec,
            r.logical_reads,
            DB_NAME(r.database_id) AS DatabaseName,
            SUBSTRING(t.text, 1, 200) AS QueryText
        FROM sys.dm_exec_requests r
        CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
        WHERE r.session_id > 50
            AND r.session_id != @@SPID
        ORDER BY r.total_elapsed_time DESC
        """

        cursor.execute(query)
        queries = cursor.fetchall()

        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        alerts = []

        for q in queries:
            alert = ""

            # Check for timeout risk
            if q.ElapsedSec > self.alert_threshold:
                alert = f"TIMEOUT_RISK ({q.ElapsedSec:.1f}s)"
                alerts.append((q.session_id, q.ElapsedSec))

            # Check for blocking
            if q.blocking_session_id and q.blocking_session_id > 0:
                alert += " BLOCKED"

            # Log to CSV
            self.csv_writer.writerow([
                timestamp,
                q.session_id,
                q.status,
                q.command,
                f"{q.ElapsedSec:.2f}",
                q.wait_type or "",
                q.blocking_session_id or "",
                q.DatabaseName,
                str(q.QueryText)[:100] if q.QueryText else "",
                alert
            ])

            # Print alerts to console
            if alert:
                print(f"[{timestamp}] ⚠ Session {q.session_id}: {alert}")
                if q.QueryText:
                    print(f"  Query: {str(q.QueryText)[:100]}...")

        return len(queries), alerts

    def check_blocking_chains(self):
        """Check for blocking chain issues"""
        cursor = self.connection.cursor()

        cursor.execute("""
        WITH BlockingChain AS (
            SELECT
                r1.session_id AS BlockedSession,
                r1.blocking_session_id AS BlockingSession,
                r1.wait_time / 1000.0 AS WaitSec,
                r1.wait_type,
                1 AS Level
            FROM sys.dm_exec_requests r1
            WHERE r1.blocking_session_id > 0

            UNION ALL

            SELECT
                r2.session_id,
                r2.blocking_session_id,
                r2.wait_time / 1000.0,
                r2.wait_type,
                bc.Level + 1
            FROM sys.dm_exec_requests r2
            INNER JOIN BlockingChain bc ON r2.blocking_session_id = bc.BlockedSession
            WHERE bc.Level < 5
        )
        SELECT * FROM BlockingChain
        ORDER BY Level, WaitSec DESC
        """)

        chains = cursor.fetchall()
        if chains:
            print("\n⚠ BLOCKING CHAIN DETECTED:")
            for chain in chains:
                print(f"  Level {chain.Level}: Session {chain.BlockedSession} blocked by {chain.BlockingSession} ({chain.WaitSec:.1f}s)")

    def get_performance_stats(self):
        """Get overall performance statistics"""
        cursor = self.connection.cursor()

        # Get wait statistics
        cursor.execute("""
        SELECT TOP 5
            wait_type,
            wait_time_ms / 1000.0 AS TotalWaitSec,
            waiting_tasks_count AS WaitCount,
            wait_time_ms / NULLIF(waiting_tasks_count, 0) / 1000.0 AS AvgWaitSec
        FROM sys.dm_os_wait_stats
        WHERE wait_type NOT IN (
            'SLEEP_TASK', 'BROKER_TASK_STOP', 'WAITFOR',
            'LAZYWRITER_SLEEP', 'CHECKPOINT_QUEUE'
        )
        ORDER BY wait_time_ms DESC
        """)

        waits = cursor.fetchall()

        print("\n[Top Wait Types]")
        for wait in waits:
            print(f"  {wait.wait_type}: {wait.TotalWaitSec:.1f}s total, {wait.AvgWaitSec:.2f}s avg")

    def run(self):
        """Main monitoring loop"""
        if not self.connect():
            return

        self.setup_logging()
        print(f"\n✓ Monitoring started (checking every {MONITOR_INTERVAL} seconds)")
        print("Press Ctrl+C to stop monitoring\n")

        iteration = 0

        try:
            while True:
                iteration += 1

                # Monitor queries
                query_count, alerts = self.monitor_queries()

                # Flush CSV buffer
                self.csv_file.flush()

                # Every 12 iterations (1 minute), check for blocking chains
                if iteration % 12 == 0:
                    self.check_blocking_chains()

                # Every 60 iterations (5 minutes), show performance stats
                if iteration % 60 == 0:
                    self.get_performance_stats()

                # Status update every 6 iterations (30 seconds)
                if iteration % 6 == 0:
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] Monitoring... {query_count} active queries")

                time.sleep(MONITOR_INTERVAL)

        except KeyboardInterrupt:
            print("\n\n✓ Monitoring stopped")
        finally:
            self.cleanup()

    def cleanup(self):
        """Clean up resources"""
        if self.csv_file:
            self.csv_file.close()
            print(f"✓ Performance log saved to {LOG_FILE}")

        if self.connection:
            self.connection.close()

    def analyze_log(self):
        """Analyze the collected performance data"""
        print("\n" + "="*60)
        print("PERFORMANCE ANALYSIS")
        print("="*60)

        if not os.path.exists(LOG_FILE):
            print("No log file found")
            return

        timeout_queries = {}
        blocked_queries = {}
        total_rows = 0

        with open(LOG_FILE, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                total_rows += 1

                # Track timeout-risk queries
                if 'TIMEOUT_RISK' in row['Alert']:
                    session_id = row['SessionID']
                    if session_id not in timeout_queries:
                        timeout_queries[session_id] = {
                            'count': 0,
                            'max_elapsed': 0,
                            'query': row['QuerySnippet']
                        }
                    timeout_queries[session_id]['count'] += 1
                    elapsed = float(row['ElapsedSec'])
                    if elapsed > timeout_queries[session_id]['max_elapsed']:
                        timeout_queries[session_id]['max_elapsed'] = elapsed

                # Track blocked queries
                if row['BlockingSession']:
                    blocker = row['BlockingSession']
                    if blocker not in blocked_queries:
                        blocked_queries[blocker] = 0
                    blocked_queries[blocker] += 1

        print(f"\nAnalyzed {total_rows} monitoring records")

        if timeout_queries:
            print("\n[Sessions with Timeout Risk]")
            for session_id, data in sorted(timeout_queries.items(),
                                         key=lambda x: x[1]['max_elapsed'],
                                         reverse=True)[:5]:
                print(f"  Session {session_id}:")
                print(f"    Occurrences: {data['count']}")
                print(f"    Max Duration: {data['max_elapsed']:.1f}s")
                print(f"    Query: {data['query'][:80]}...")

        if blocked_queries:
            print("\n[Top Blocking Sessions]")
            for blocker, count in sorted(blocked_queries.items(),
                                        key=lambda x: x[1],
                                        reverse=True)[:5]:
                print(f"  Session {blocker}: blocked {count} queries")

def main():
    print("="*60)
    print("QUERY PERFORMANCE MONITOR")
    print("="*60)
    print(f"Server: {SERVER}:{PORT}")
    print(f"Database: {DATABASE}")

    username = input("\nSQL Username: ")
    password = input("SQL Password: ")

    monitor = QueryMonitor(username, password)

    # Check if we should analyze existing log
    if os.path.exists(LOG_FILE):
        choice = input("\nExisting log found. (M)onitor or (A)nalyze? ").lower()
        if choice == 'a':
            monitor.analyze_log()
            return

    # Start monitoring
    monitor.run()

    # Analyze after monitoring
    choice = input("\nAnalyze collected data? (Y/N): ").lower()
    if choice == 'y':
        monitor.analyze_log()

if __name__ == "__main__":
    main()
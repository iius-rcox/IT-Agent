# SQL Server Timeout Fix & Health Check Tools for pVault

## 🚨 CRITICAL: pVault Invoice Timeout Issue Resolution

This directory contains comprehensive SQL Server health check and timeout resolution scripts for the pVault SQL Server instance experiencing **"Execution Timeout Expired"** errors.

## Server Configuration
- **Server**: inscolpvault.insulationsinc.local
- **Port**: 55859 (non-standard)
- **Database**: PaperlessEnvironments
- **Type**: Microsoft SQL Server on Azure VM
- **Access**: VPN required
- **Known Issue**: LoadInvoicesByStatusID timeout errors

## ⚡ QUICK FIX STEPS FOR TIMEOUT ERRORS

### Step 1: Run Emergency Fix (Immediate Relief)
```sql
-- Run this SQL script directly in SSMS or Azure Data Studio
sqlcmd -S inscolpvault.insulationsinc.local,55859 -U sa -i emergency_timeout_fix.sql
```

### Step 2: Diagnose Invoice-Specific Issues
```bash
cd inscolpvault
python diagnose_invoice_timeout.py
```

### Step 3: Monitor Performance
```bash
python monitor_query_performance.py
```

## 📁 Available Scripts

### 🆘 Emergency Response Scripts

#### **emergency_timeout_fix.sql**
**Purpose**: Immediate SQL script to resolve timeout issues
**What it does**:
- Updates all statistics (forces query reoptimization)
- Clears query plan cache (removes bad execution plans)
- Identifies and suggests missing indexes
- Rebuilds fragmented indexes on invoice tables
- Shows current blocking sessions

**Usage**:
```sql
-- Run in SSMS or Azure Data Studio
-- Or via command line:
sqlcmd -S inscolpvault.insulationsinc.local,55859 -U sa -i emergency_timeout_fix.sql
```

#### **diagnose_invoice_timeout.py**
**Purpose**: Specifically diagnoses invoice-related timeout issues
**What it does**:
- Analyzes invoice table sizes and row counts
- Checks indexes on invoice/status tables
- Identifies missing indexes for invoice queries
- Reviews invoice query performance history
- Checks statistics freshness on invoice tables
- Monitors currently running invoice queries
- Generates fix scripts

**Usage**:
```bash
python diagnose_invoice_timeout.py
```

### 📊 Monitoring Scripts

#### **monitor_query_performance.py**
**Purpose**: Real-time query performance monitoring
**Features**:
- Monitors queries every 5 seconds
- Logs performance data to CSV
- Alerts on queries approaching timeout (>20 seconds)
- Detects blocking chains
- Tracks wait statistics
- Analyzes patterns over time

**Usage**:
```bash
# Start monitoring
python monitor_query_performance.py

# Analyze existing log
python monitor_query_performance.py
# Choose 'A' for analyze when prompted
```

### 🔍 Diagnostic Scripts

#### **quick_health_check.py**
**Purpose**: Fast health check without dependencies
**Features**:
- No pandas required (uses only pyodbc)
- Quick database status check
- Blocking detection
- Long-running query identification
- Resource usage summary

**Usage**:
```bash
python quick_health_check.py
```

#### **sql_health_check.py** (Enhanced with Timeout Analysis)
**Purpose**: Comprehensive health check with timeout-specific diagnostics
**New Features Added**:
- **Query Timeout Detection**: Identifies queries approaching 30-second timeout
- **Large Table Analysis**: Finds tables >100k rows causing timeouts
- **Missing Index Detection**: SQL Server recommended indexes
- **Index Fragmentation**: Indexes needing rebuild (>30% fragmentation)
- **Statistics Age Analysis**: Outdated statistics causing bad plans

**Usage**:
```bash
# Install dependencies first (if not already done)
pip install -r requirements_sql.txt

# Run comprehensive check
python sql_health_check.py
```

#### **test_sql_connection.py**
**Purpose**: Verify connectivity before running diagnostics
**Features**:
- Tests multiple ODBC drivers (18, 17, Native Client)
- Provides specific error troubleshooting
- Lists available databases

**Usage**:
```bash
python test_sql_connection.py
```

### 🔧 Utility Scripts

#### **run_sql_health_check.py**
**Purpose**: Non-interactive health check for automation
**Usage**:
```bash
python run_sql_health_check.py --username sa --password YOUR_PASSWORD
```

#### **sql_health_check.ps1**
**Purpose**: PowerShell alternative (no Python needed)
**Usage**:
```powershell
.\sql_health_check.ps1
```

## 🎯 Timeout Issue Resolution Workflow

### Immediate Actions (Do First)
1. **Check Current Activity**:
   ```bash
   python quick_health_check.py
   ```
   Look for blocking sessions and long-running queries

2. **Run Emergency Fix**:
   ```sql
   -- Execute emergency_timeout_fix.sql in SSMS
   ```

3. **Diagnose Invoice Issues**:
   ```bash
   python diagnose_invoice_timeout.py
   ```

### Root Cause Analysis
1. **Start Performance Monitor**:
   ```bash
   python monitor_query_performance.py
   ```
   Let it run for 10-15 minutes during normal operations

2. **Run Full Health Check**:
   ```bash
   python sql_health_check.py
   ```

3. **Review Results** for:
   - Missing indexes (most common cause)
   - Fragmented indexes (>50% fragmentation)
   - Outdated statistics
   - Large tables without proper indexing

### Long-Term Fixes

#### 1. Create Missing Indexes
The diagnostic scripts will generate CREATE INDEX statements. Review and execute:
```sql
-- Example from diagnostic output
CREATE INDEX IX_Invoice_StatusID
ON dbo.Invoices (StatusID)
INCLUDE (InvoiceDate, CustomerID, TotalAmount)
```

#### 2. Schedule Regular Maintenance
```sql
-- Weekly index maintenance
ALTER INDEX ALL ON dbo.Invoices REBUILD WITH (ONLINE = ON)

-- Daily statistics update
UPDATE STATISTICS dbo.Invoices WITH FULLSCAN
```

#### 3. Application-Level Fix
In your pVault application code:
```csharp
// Increase timeout from default 30 to 60 seconds
command.CommandTimeout = 60;

// Or in connection string
"...;Command Timeout=60;..."
```

## 📈 Performance Indicators

### 🔴 Critical (Immediate Action)
- Queries running >25 seconds (timeout imminent)
- Blocking chains detected
- Missing indexes with impact score >10000
- Index fragmentation >70%
- Statistics >30 days old with >10k modifications

### 🟡 Warning (Plan Action)
- Queries running 15-25 seconds
- Tables >1M rows without clustered index
- Index fragmentation 30-70%
- Statistics >7 days old

### 🟢 Healthy
- All queries <10 seconds
- No blocking detected
- Recent statistics (<7 days)
- Index fragmentation <30%

## 🛠️ Prerequisites

### Python Scripts
- Python 3.7+
- ODBC Driver 18 or 17 for SQL Server
- pyodbc library (`pip install pyodbc`)
- Optional: pandas, tabulate for full health check

### PowerShell Script
- PowerShell 5.0+
- .NET Framework with System.Data.SqlClient

### SQL Scripts
- SQL Server Management Studio (SSMS)
- Or Azure Data Studio
- Or sqlcmd command-line tool

## 🔒 Security Notes
- Never commit credentials to version control
- Use secure credential storage for automation
- Ensure VPN connection is encrypted
- Limit access to diagnostic outputs (may contain sensitive schema info)

## 📞 Support Escalation

### For Timeout Issues:
1. Run `diagnose_invoice_timeout.py` first
2. Share output with DBA team
3. Implement recommended indexes
4. Monitor with `monitor_query_performance.py`

### For Persistent Issues:
- **Database Team**: For index/statistics optimization
- **Application Team**: For query optimization in code
- **Infrastructure Team**: For server resource issues

## 📝 Change Log

### 2025-11-12 Updates:
- Added emergency_timeout_fix.sql for immediate relief
- Created diagnose_invoice_timeout.py for specific issue
- Added monitor_query_performance.py for real-time tracking
- Enhanced sql_health_check.py with timeout analysis
- Updated all scripts with correct port (55859) and database (PaperlessEnvironments)
- Added comprehensive timeout resolution workflow

## 💡 Tips for Success

1. **Always run diagnostics first** - Don't guess at the problem
2. **Monitor before and after changes** - Verify improvements
3. **Test index changes in dev first** - If possible
4. **Document what fixed the issue** - For future reference
5. **Set up alerts** - For queries >20 seconds
6. **Regular maintenance** - Prevent issues before they occur

---

**Remember**: Most timeout issues are caused by:
- Missing indexes (70% of cases)
- Outdated statistics (20% of cases)
- Blocking/locking (10% of cases)

Run the diagnostic scripts to identify which applies to your situation!
# SQL Server Health Check Tools for pvault

This directory contains comprehensive SQL Server health check scripts for diagnosing issues with the pvault SQL Server instance hosted on Azure VM.

## Server Information
- **Server**: inscolpvault.insulationsinc.local
- **Type**: Microsoft SQL Server on Azure VM
- **Access**: VPN required

## Available Scripts

### 1. test_sql_connection.py
Quick connection test script to verify connectivity before running full health checks.

**Usage:**
```bash
python test_sql_connection.py
```

**Features:**
- Tests multiple ODBC driver options
- Lists available drivers on your system
- Provides detailed error messages and troubleshooting steps
- Shows available databases on successful connection

### 2. sql_health_check.py
Comprehensive health check script that performs detailed diagnostics.

**Usage:**
```bash
# First install dependencies
pip install -r requirements_sql.txt

# Run the health check
python sql_health_check.py
```

**Health Checks Performed:**
- Server information and version
- Database status and configuration issues
- CPU usage analysis (last hour)
- Memory usage and pressure indicators
- Top wait statistics
- Blocking session detection
- Long-running queries (>30 seconds)
- Database file sizes and growth settings
- Recent error log entries

### 3. sql_health_check.ps1
PowerShell alternative that doesn't require Python dependencies.

**Usage:**
```powershell
# Run with prompts for credentials
.\sql_health_check.ps1

# Run with parameters
.\sql_health_check.ps1 -ServerInstance "inscolpvault.insulationsinc.local" -Database "master" -Username "your_username"
```

## Prerequisites

### For Python Scripts:
1. **Python 3.7+** installed
2. **ODBC Driver for SQL Server** (one of the following):
   - ODBC Driver 17 for SQL Server (recommended)
   - ODBC Driver 18 for SQL Server
   - SQL Server Native Client 11.0

   Download from: https://docs.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server

3. **Python packages**:
   ```bash
   pip install -r requirements_sql.txt
   ```

### For PowerShell Script:
1. **PowerShell 5.0+**
2. **.NET Framework** with System.Data.SqlClient
3. Optional: **SqlServer PowerShell module**
   ```powershell
   Install-Module -Name SqlServer -AllowClobber
   ```

## Connection Requirements

1. **VPN Connection**: Must be connected to corporate VPN to access inscolpvault.insulationsinc.local

2. **SQL Authentication**: Requires SQL Server authentication (username/password), not Windows authentication

3. **Network Connectivity**: Port 1433 must be accessible

   Test connectivity:
   ```powershell
   Test-NetConnection -ComputerName inscolpvault.insulationsinc.local -Port 1433
   ```

## Troubleshooting Common Issues

### Connection Failures

1. **"Network-related or instance-specific error"**
   - Verify VPN connection is active
   - Check firewall settings
   - Confirm server name and port

2. **"Login failed for user"**
   - Verify username and password
   - Ensure SQL Server authentication is enabled (not just Windows auth)
   - Check user has necessary permissions

3. **"Driver not found"**
   - Install appropriate ODBC driver
   - Run `test_sql_connection.py` to see available drivers

4. **"Certificate error"**
   - The scripts include `TrustServerCertificate=yes` to handle self-signed certificates
   - For production, consider proper certificate configuration

## Interpreting Results

### Critical Issues to Address Immediately:
- **Blocking sessions**: Indicates queries waiting on locks
- **High CPU usage** (>80%): Performance degradation likely
- **Memory pressure warnings**: May cause query plan cache evictions
- **Databases not ONLINE**: Immediate attention required

### Performance Optimization Opportunities:
- **Long-running queries**: Review for optimization
- **High wait statistics**: Identify bottlenecks (I/O, CPU, memory)
- **AutoClose/AutoShrink enabled**: Should typically be disabled
- **Large transaction logs**: May need backup/truncation

### Regular Monitoring:
- **Database file growth**: Monitor for capacity planning
- **Error log patterns**: Look for recurring issues
- **Wait type trends**: Track over time for baseline

## Recommended Actions

1. **First Run**: Use `test_sql_connection.py` to verify connectivity
2. **Full Health Check**: Run `sql_health_check.py` for comprehensive analysis
3. **Regular Monitoring**: Schedule health checks during different load periods
4. **Document Findings**: Keep history of health check results for trend analysis

## Security Notes

- Never store credentials in scripts
- Use secure credential management for automation
- Ensure VPN connection is secure
- Limit access to health check results (may contain sensitive information)

## Support

For issues with:
- **Scripts**: Review error messages and check prerequisites
- **SQL Server**: Contact database administration team
- **Network/VPN**: Contact IT infrastructure team

## Version History

- 2025-11-12: Initial version with comprehensive health checks for pvault SQL Server
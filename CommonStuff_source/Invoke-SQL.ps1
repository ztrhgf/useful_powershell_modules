function Invoke-SQL {
    <#
    .SYNOPSIS
    Function for invoke sql command on specified SQL server.

    .DESCRIPTION
    Function for invoke sql command on specified SQL server.
    Uses Integrated Security=SSPI for making connection.

    .PARAMETER dataSource
    Name of SQL server.

    .PARAMETER database
    Name of SQL database.

    .PARAMETER sqlCommand
    SQL command to invoke.
    !Beware that name of column must be in " but value in ' quotation mark!

    "SELECT * FROM query.SwInstallationEnu WHERE `"Product type`" = 'commercial' AND `"User`" = 'Pepik Karlu'"

    .PARAMETER force
    Don't ask for confirmation for SQL command that modifies data.

    .EXAMPLE
    Invoke-SQL -dataSource SQL-16 -database alvao -sqlCommand "SELECT * FROM KindRight"

    On SQL-16 server in alvao SQL database runs selected command.

    .EXAMPLE
    Invoke-SQL -dataSource "admin-test2\SOLARWINDS_ORION" -database "SolarWindsOrion" -sqlCommand "SELECT * FROM pollers"

    On "admin-test2\SOLARWINDS_ORION" server\instance in SolarWindsOrion database runs selected command.

    .EXAMPLE
    Invoke-SQL -dataSource ".\SQLEXPRESS" -database alvao -sqlCommand "SELECT * FROM KindRight"

    On local server in SQLEXPRESS instance in alvao database runs selected command.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $dataSource
        ,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $database
        ,
        [string] $sqlCommand = $(throw "Please specify a query.")
        ,
        [switch] $force
    )

    if (!$force) {
        if ($sqlCommand -match "^\s*(\bDROP\b|\bUPDATE\b|\bMODIFY\b|\bDELETE\b|\bINSERT\b)") {
            while ($choice -notmatch "^[Y|N]$") {
                $choice = Read-Host "sqlCommand will probably modify table data. Are you sure, you want to continue? (Y|N)"
            }
            if ($choice -eq "N") {
                break
            }
        }
    }

    #TODO add possibility to connect using username/password
    # $connectionString = 'Data Source={0};Initial Catalog={1};User ID={2};Password={3}' -f $dataSource, $database, $userName, $password
    $connectionString = 'Data Source={0};Initial Catalog={1};Integrated Security=SSPI' -f $dataSource, $database

    $connection = New-Object system.data.SqlClient.SQLConnection($connectionString)
    $command = New-Object system.data.sqlclient.sqlcommand($sqlCommand, $connection)
    $connection.Open()

    $adapter = New-Object System.Data.sqlclient.sqlDataAdapter $command
    $dataset = New-Object System.Data.DataSet
    $adapter.Fill($dataSet) | Out-Null

    $connection.Close()
    $adapter.Dispose()
    $dataSet.Tables
}

# Automation of Postgres Foreign Tables


# Who?

* Chad Slaughter <chad@scalegenius.com>
* Co-Founder
* Scale Genius, Inc

# What?

## Postgres Foreign Tables

* SQL Standard: SQL/MED
* Access External Data
  * Flat Files
  * Relational Databases
  * <https://wiki.postgresql.org/wiki/Foreign_data_wrappers>
* <https://github.com/scalegenius/generate-foreign-tables/blob/chipug/docs/ft-describe.svg>

# Why?

* Better Software Development Practice
* Easier to Track Changes
* Improved Testing
  * <https://github.com/slaught/dummy_fdw>
* Simplified Operations

# How?

* <https://github.com/scalegenius/generate-foreign-tables>

This generates Foreign table definitions to be loaded into a PostgreSQL
databases to access remote tables in PostgreSQL, Mysql, and SQL Server.

## Arguments

### Requires

* ``-c <connection_string>`` is a Database URL for specifing connection information.
* ``-n <server_name>``  is the Foreign Server name to use.

### Optional

* ``-schema <remote_schema>`` is the remote schema to search for tables.
* ``-mv`` causes Materialized Views to be generated as a caching layer on the Foreign Tables.
* ``-debug`` Enable debug output


## Database URL

The required option ``-c`` takes a Database URL as an argument.

Database URLs using the standard URL enocoding for username, password,
hostname, and port. The name of the database and other options are encoded in
the path. The URL scheme is the type of database: postgresql, mysql, or sqlserver.

For a mysql database named ``dbexample`` at DNS hostname ``host`` on port
``1234`` with access credentials of ``user`` and ``password``. This would
written as follows: ``mysql://user:password@host:1234/dbexample``

## Example Usage

### Example Invocation

We assume out Foreign Server name is ``mysql_server``. And we will redirect
the output to file `ft.sql``.

``bundle exec ./generate_foreign_tables.rb -c mysql://user:password@host:1234/dbexample -n mysql_server > ft.sql``





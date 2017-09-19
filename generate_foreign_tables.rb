#!/usr/bin/env ruby
# usage: generate -n <connection_name> -c <connection_string>
# arg parsing to handle db conn info

require "rubygems"
require "bundler/setup"


require 'active_record'
require 'Getopt/Declare'

require 'activerecord-sqlserver-adapter'
require 'pg'

require 'uri'

$DEBUG = false

def get_args
@args = Getopt::Declare.new(<<EOF)
     -c <connection_string>         connection string for access db   [required]
     -n <connection_name>           Server name to use                [required]
     -schema <remote_schema>        Remote Tables from given Schema
     -mv                            Materialized Views as caching layer on Foreign Tables
     -debug                         enable debug output
                                           {$DEBUG = true }
     -on-duplicate-fail             Fail if there are duplicate table names
     -fix-mysql-date                Fix dates from Mysql database

EOF
end

module Quoting
    def quote(x)
      PGconn.quote_ident(x)
    end
end

module InfoCatalog
    include Quoting
    def build(schema)
        tables = tables(schema)
        # STDERR.puts tables.inspect
        tables_columns = tables.map {|t|
           t["columns"] = get_table_columns(t["schema_name"],t["table_name"])
           t
        }
    end
    def tables(schema_to_limit)
        user_tables(schema_to_limit).to_a
    end
    def user_tables(schema_to_limit)
        if schema_to_limit.nil? then
          clause = '/* all schemas */'
        else
          clause = %Q(where table_schema = '#{schema_to_limit}')
        end
        connection.exec_query(%Q(
            select
               table_schema  as schema_name
             , table_name
             , table_type
            from information_schema.tables
            #{clause}
            order by 1,2
           )
        )
    end
    # Returns Array of Columns
    def get_table_columns(schema_name, table_name)
        cols = table_columns(schema_name, table_name)
        STDERR.puts cols.inspect if $DEBUG
        cols.map{ |col| column_struct(col) }
    end
    def table_columns(schema_name, table_name)
      connection.exec_query(%Q(SELECT
            table_schema
          , table_name
          , column_name
          , ordinal_position
          , data_type as column_type
          , character_maximum_length, numeric_precision, numeric_scale
          , #{_display_type_colname} as display_type
          FROM information_schema.columns
        where table_schema  = '#{schema_name}'
          and table_name = '#{table_name}'
        ORDER BY ordinal_position)
      )
    end
    def has_extra_display_type?
        false
    end
    def extra_display_type_colname
        raise NotImplemented.new("Subclass must implement extra_display_type_colname method")
    end
    def null_format(column_type)
        raise NotImplemented.new("Subclass must implement null_format method")
    end
    def _display_type_colname
        if has_extra_display_type? then
            extra_display_type_colname
        else
            "data_type"
        end
    end
    def convert_type( t, m, p, s)
        raise NotImplemented.new("Subclass must implement convert_type method")
    end
    def column_struct(col)
      t = convert_type(col["column_type"], col["character_maximum_length"],col["numeric_precision"],col["numeric_scale"])
      [quote(col["column_name"]), t, col["display_type"] ]
      TableColumnAST.create(col, self.has_extra_display_type?, t, null_format(col["column_type"]))
    end
    def convert_numeric(column_type, numeric_precision,numeric_scale)
            if numeric_precision then
                if numeric_scale then
                  "#{column_type}(#{numeric_precision},#{numeric_scale})"
                else
                  "#{column_type}(#{numeric_precision})"
                end
            else
                  columm_type
            end
    end
    def convert_chars(column_type, character_maximum_length)
         if character_maximum_length and character_maximum_length.to_i < 129 and character_maximum_length.to_i > 0 then
            "#{column_type}(#{character_maximum_length})"
         else
            "text"
         end
    end
end

#    def self.convert_type(column_type, character_maximum_length,numeric_precision,numeric_scale)
class TableAST
  attr_reader :schema_name, :table_name
  attr_accessor :columns
  def initialize(_q) # table hash
    @schema_name = _q["schema_name"]
    @table_name = _q["table_name"]
    @columns = _q["columns"]
  end
  def add(_col)
    raise Exception.new('wrong class for column') unless _col.class == TableColumnAST
    @table_columns << _col
  end
end
class TableColumnAST
  attr_accessor :column_name, :column_type
  attr_accessor :display_type, :postgres_type
  attr_accessor :is_date
  attr_accessor :date_column_null

  include Quoting
 
  def is_date_column?
      not date_column_null.nil?
  end
  def initialize()
  end
  def name
      quote(@column_name.downcase)
  end
  def self.create(col, has_extra_display_type, new_postgres_type, _date_column_null)
    c = new
    c.display_type = if has_extra_display_type then
        col["display_type"]
    else
       guess_type(col["column_type"], col["character_maximum_length"],col["numeric_precision"],col["numeric_scale"])
    end
    c.column_type = col["column_type"]
    c.column_name = col["column_name"]
    c.postgres_type = new_postgres_type
    c.date_column_null = _date_column_null if _date_column_null
    c
  end
   def self.guess_type(column_type, character_maximum_length, numeric_precision, numeric_scale)
       if numeric_precision then
          if numeric_scale then
                  "#{column_type}(#{numeric_precision},#{numeric_scale})"
          else
                  "#{column_type}(#{numeric_precision})"
          end
        else
          if character_maximum_length then
            "#{column_type}(#{character_maximum_length})"
          else
            column_type
          end
        end
  end
#############
end

class PgCatalog < ActiveRecord::Base

    self.table_name = "pg_class"

    class << self
        include InfoCatalog
        include Quoting
    end
    def self.null_format(c)
        nil
    end
    def self.build(_schema)
        tables = self.tables(_schema)
        tables_columns = tables.map {|t|
           t["columns"] = self.get_table_columns(t["oid"])
           t
        }
    end
    def self.user_tables(limit_to_schema)
        if limit_to_schema.nil? then
          clause = '/* all schemas */'
        else
          clause = %Q(where schemaname = '#{limit_to_schema}')
        end
        connection.execute(%Q(
            select
                   schemaname as schema_name
                ,  relname as table_name
                ,  relid as oid
            from pg_stat_user_tables
            #{clause}
            order by 1,2
           )
        )
    end
    def self.table_columns(table_oid)
      connection.execute("SELECT
            a.attname as column_name
        /* , a.attnum as ordinal_position */
          , format_type(coalesce(nullif(t.typbasetype, 0), a.atttypid), a.atttypmod) as column_type
          , t.typtype as attribute_type
          , t.typbasetype as base_type_oid
/* typtype is b: base type,
              c for a composite type ,
              d for a domain,
              e for an enum type,
              p for a pseudo-type,
              r for a range type
*/
        FROM pg_attribute a
        JOIN pg_class c ON c.oid = a.attrelid
        JOIN pg_type t on t.oid = a.atttypid
        WHERE a.attnum > 0
          AND c.oid = a.attrelid
          AND NOT a.attisdropped
          AND c.oid = #{table_oid.to_i}
        ORDER BY a.attnum")
    end
    def self.tables(limit_to_schema=nil)
        user_tables(limit_to_schema).to_a
    end
    def self.get_table_columns(table_oid)
        cols = PgCatalog.table_columns(table_oid)
        cols.map{ |col|  # [quote(col["column_name"]), col["column_type"], col["column_type"]]
                TableColumnAST.create(col, false, col["column_type"], nil)
        }
    end
end

class MysqlCatalog < ActiveRecord::Base
    self.table_name = "columns"
    class << self
        include InfoCatalog
    end
    def self.has_extra_display_type?
        true
    end
    def self.extra_display_type_colname
        "column_type"
    end
    def self.null_format(column_type)
        case column_type
        when "date" then
           ['0000-00-00', 'date']
        when "datetime" then
           ['0000-00-00 00:00:00', 'timestamp']
        when "timestamp" then
           ['0000-00-00 00:00:00', 'timestamp']
        else
           nil
        end
    end
    # t = convert_type(col["column_type"], col["character_maximum_length"],col["numeric_precision"],col["numeric_scale"])
    def self.convert_type(column_type, character_maximum_length,numeric_precision,numeric_scale)
        case column_type
        when "numeric" then
            convert_numeric(column_type, numeric_precision,numeric_scale)
        when "decimal" then
            convert_numeric(column_type, numeric_precision,numeric_scale)
        when "char" then
            convert_chars(column_type, character_maximum_length )
        when "varchar" then
            convert_chars(column_type, character_maximum_length )
        when "bit" then
            if character_maximum_length then
              "bit(#{character_maximum_length})"
            else
              "bit"
            end
        when "text" then
            "text"
        when "tinytext" then
            "text"
        when "mediumtext" then
            "text"
        when "longtext" then
            "text"
        when "binary" then
            "bytea"
        when "varbinary" then
            "bytea"
        when "blob" then
            "bytea"
        when "tinyblob" then
            "bytea"
        when "mediumblob" then
            "bytea"
        when "longblob" then
            "bytea"
        when "tinyint" then
            "int"
        when "smallint" then
            "int"
        when "mediumint" then
            "int"
        when "int" then
            "int"
        when "bigint" then
            "bigint"
        when "enum" then
            "text"
        when "set" then
            "text"
        when "float" then
            "real"
        when "real" then
            "real"
        when "double"
            "double precision"
        when "double precision"
            "double precision"
        when "datetime" then
          "text"
        when "year" then
          "text"
        when "date" then
          "text"
        when "time" then
          "text"
        when "timestamp" then
          "text"
        else
            STDERR.puts "Unknown type : #{column_type}"
        end
    end
end
class SqlserverCatalog < ActiveRecord::Base
    self.table_name = "columns"
    class << self
        include InfoCatalog
    end
    def self.has_extra_display_type?
        false
    end
    def self.null_format(column_type)
      nil
    end
    # t = convert_type(col["column_type"], col["character_maximum_length"],col["numeric_precision"],col["numeric_scale"])
    def self.convert_type(column_type, character_maximum_length,numeric_precision,numeric_scale)
        case column_type
        when "numeric" then
            convert_numeric(column_type, numeric_precision,numeric_scale)
        when "decimal" then
            convert_numeric(column_type, numeric_precision,numeric_scale)
        when "char" then
            convert_chars(column_type, character_maximum_length )
        when "varchar" then
            convert_chars(column_type, character_maximum_length )
        when "nvarchar" then
            convert_chars("varchar", character_maximum_length )
        when "nchar" then
            convert_chars("char", character_maximum_length )
        when "bit" then
            if character_maximum_length then
              "bit(#{character_maximum_length})"
            else
              "bit"
            end
        when "text" then
            "text"
        when "tinytext" then
            "text"
        when "mediumtext" then
            "text"
        when "longtext" then
            "text"
        when "binary" then
            "bytea"
        when "varbinary" then
            "bytea"
        when "blob" then
            "bytea"
        when "tinyblob" then
            "bytea"
        when "mediumblob" then
            "bytea"
        when "longblob" then
            "bytea"
        when "tinyint" then
            "int"
        when "smallint" then
            "int"
        when "mediumint" then
            "int"
        when "int" then
            "int"
        when "bigint" then
            "bigint"
        when "enum" then
            "text"
        when "set" then
            "text"
        when "float" then
            "real"
        when "real" then
            "real"
        when "double"
            "double precision"
        when "double precision"
            "double precision"
        when "date" then
          "date"
        when "time" then
          "time"
        when "smalldatetime" then
          "timestamp"
        when "datetime" then
          "timestamp"
        when "datetime2" then
          "timestamp"
        when "timestamp" then
          "timestamp"
        when "datetimeoffset" then
          "timestamp with time zone"
        when "smallmoney" then
          "money"
        when "money" then
          "money"
        when "xml" then
          "xml"
        when "uniqueidentifier" then
          "text"
        else
            STDERR.puts "Unknown type : #{column_type}"
        end
    end
end

class DatabaseCatalog
    attr_accessor :catalog
    def initialize(vendor)
      @catalog = case vendor
      when "mysql" then
          MysqlCatalog
      when "mysql2" then
          MysqlCatalog
      when "sqlserver" then
          SqlserverCatalog
      when "postgresql" then
          PgCatalog
      else
        raise Exception.new("Unknown catalog type: #{vendor}")
      end
    end
    def build(schema)
        @catalog.build(schema)
    end
end


class Names
  def initialize(on_duplicate_fail=false)
    @seen = Hash.new(0)
    @on_duplicate_fail = on_duplicate_fail
  end
  def seen(v)
    if @seen.key? v then
      duplicate(v)
    end
    @seen[v] = @seen[v] + 1
    nil
  end
  def on_duplicate_fail!
    @on_duplicate_fail = true
  end
  def duplicate(v)
     msg =  "Duplicate table name created: #{v}"
    if @on_duplicate_fail then
        raise Exception.new(msg)
    else
      STDERR.puts "Warning: #{msg}"
    end
  end
  def duplicates
      @seen.map {|k,v| if v > 1 then k else nil end }.compact
  end
end

class Formatter
  attr_accessor :server_name
  attr_accessor :vendor_name
  include Quoting
  def initialize(vendor, mv, mysql_fixup=nil)
    self.vendor_name=vendor
    @col_types = Array.new
    @names = Names.new
    if self.vendor_name =~ /mysql/ then 
      @format = Formatter.determine_format(mv, mysql_fixup)  # only fixup on mysql date
    else
      @format = Formatter.determine_format(mv, false) 
    end
  end
  #format is "fdw", optional ( mv | mysqldate) ,  "format" 
  # all seperate by underscores 
  def self.determine_format(mv, mysql_fixup)
    formats = []
    if not mv.nil? then
      formats << "mv" 
    end
    if mysql_fixup then 
      formats.push "mysqldate"
    end
    formats.unshift "fdw"
    formats.push    "format"
    formats.join("_").to_sym
  end
  def name_seen(v)
    @names.seen(v)
  end
  def format(args)
    STDERR.puts args.class if $DEBUG
    table = args.table_name
    schema= args.schema_name
    cols = args.columns
    STDERR.puts "#{table.inspect} #{schema.inspect} #{cols.inspect}" if $DEBUG
    send(@format,schema,table,cols)
  end
  # returns printable column_list # = mysqldate_fix_columns(columns)
  def mysqldate_fix_columns(columns)
      #return "*" unless @format.to_s =~ /mysql/
      columns.map{|col|
          if col.is_date_column? then 
             fmt, newtype = col.date_column_null
             %Q[nullif(#{col.name}, '#{fmt}')::#{newtype} as #{col.name}]
          else
              col.name
          end
      }.join(",\n            ")
  end
  def fdw_mv_mysqldate_format(remote_schema, remote_table, columns)
      column_list = mysqldate_fix_columns(columns)
      fdw_mv_format(remote_schema, remote_table, columns, column_list)
  end
  def fdw_mysqldate_format(remote_schema, remote_table, columns)
      table = remote_table.downcase
      name_seen(table)
      ft_name = "_#{table.downcase}"
      column_list = mysqldate_fix_columns(columns)
      ft_definition = fdw_format(remote_schema, remote_table, columns, ft_name )
  %Q[
    DROP VIEW IF EXISTS #{quote(table)};
#{ft_definition}
    CREATE VIEW #{quote(table)} as
          select #{column_list} from #{quote(ft_name)}
    ;]
  end
  def fdw_mv_format(remote_schema, remote_table, columns,column_list="*")
    table = remote_table.downcase
    ft_name = "_#{table.downcase}"
    name_seen(table)
    ft_definition = fdw_format(remote_schema, remote_table, columns, ft_name )
  %Q[
    DROP MATERIALIZED VIEW IF EXISTS #{quote(table)};
#{ft_definition}
    CREATE MATERIALIZED VIEW #{quote(table)} as
          select #{column_list} from #{quote(ft_name)}
    WITH NO DATA;]
  end
  def column_comment(ft_name, col)
    %Q[COMMENT on COLUMN #{quote(ft_name)}.#{col.name} IS $$remote type: #{col.display_type}$$;]
  end
  def column_comments(ft_name, columns)
    columns.map { |col|   column_comment(ft_name, col) }.join("\n")
  end
  def fdw_format(remote_schema, remote_table, columns, local_table=nil)
    local_table = remote_table if local_table.nil?
    cols = columns.map{|x| "#{x.name} #{x.postgres_type}" }.join(",\n       ")
    @col_types <<  columns.map{|x| x.display_type  }.uniq

    ft_name = local_table.downcase
    name_seen(ft_name)
  %Q[
    DROP FOREIGN TABLE IF EXISTS #{quote(ft_name)};
    CREATE FOREIGN TABLE #{quote(ft_name)}
      (#{cols})
    SERVER "#{self.server_name}"
    OPTIONS (#{options(remote_table, remote_schema)}
    );
#{column_comments(ft_name, columns)}]
  end
  def options(remote_table, remote_schema)
      send("#{vendor_name}_options".to_sym, remote_table, remote_schema)
  end
  def postgresql_options(remote_table, remote_schema)
    %Q[
      schema_name '#{remote_schema}',
      table_name  '#{remote_table}']
  end
  def sqlserver_options(remote_table, remote_schema)
    # SQLServer
    %Q[table '#{remote_table}']
  end
  def mysql2_options(remote_table, remote_schema)
      mysql_options(remote_table, remote_schema)
  end
  def mysql_options(remote_table, remote_schema)
    %Q[
      dbname     '#{remote_schema}',
      table_name '#{remote_table}']
  end
  def find_missing_types
    @col_types = @col_types.flatten.uniq
    @col_types
  end
  def warnings
    { "types" => find_missing_types,
      "duplicate names" => @names.duplicates
    }
  end
end

def db_connect(connection_url)
    begin
      ActiveRecord::Base.establish_connection(connection_url)
    rescue URI::InvalidURIError
      connection_url = URI::encode(@args['-c'])
      ActiveRecord::Base.establish_connection(connection_url)
    end
    connection_url.split(':').first
end

def main()
    @args = get_args
    STDERR.puts @args.inspect if $DEBUG

    db_vendor = db_connect(@args['-c'])

    #     -fix-mysql-date                Fix dates from Mysql database
    @format = Formatter.new(db_vendor, @args['-mv'],@args['-fix-mysql-date'])
    @format.server_name = @args['-n']
    @format.on_duplicate_fail! if @args['-on-duplicate-fail']

    c = DatabaseCatalog.new(db_vendor)
    tables_columns = c.build(@args['-schema'])
    STDERR.puts tables_columns.to_a.inspect if $DEBUG

    output = tables_columns.map do |table|
       t = TableAST.new(table)
       @format.format(t)
    end

    puts output.join("\n")
    STDERR.puts @format.warnings.inspect if $DEBUG
end
main()

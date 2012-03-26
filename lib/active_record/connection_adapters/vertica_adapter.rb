require 'active_record/connection_adapters/abstract_adapter'
require 'active_support/core_ext/kernel/requires'

module ActiveRecord
  class Base
    # Establishes a connection to the database that's used by all Active Record objects
    def self.vertica_connection(config) # :nodoc:
      unless defined? Vertica
        begin
          require 'vertica'
        rescue LoadError
          raise "!!! Missing the vertica gem. Add it to your Gemfile: gem 'vertica'"
        end
      end

      config = config.symbolize_keys
      host     = config[:host]
      port     = config[:port] || 5433
      username = config[:username].to_s if config[:username]
      password = config[:password].to_s if config[:password]

      if config.has_key?(:database)
        database = config[:database]
      else
        raise ArgumentError, "No database specified. Missing argument: database."
      end
      if config.has_key?(:schema)
        schema = config[:schema]
      else
        raise ArgumentError, "No database specified. Missing argument: schema."
      end
      conn = Vertica.connect({ :user => username, :password => password, :host => host, :port => port, :database => database , :schema => schema})
      ConnectionAdapters::Vertica.new(conn)
    end

    class << self
      def instantiate(record)
        record.stringify_keys!
        
        sti_class = find_sti_class(record[inheritance_column])
        record_id = sti_class.primary_key && record[sti_class.primary_key]
        if ActiveRecord::IdentityMap.enabled? && record_id
          if (column = sti_class.columns_hash[sti_class.primary_key]) && column.number?
            record_id = record_id.to_i
          end
          if instance = IdentityMap.get(sti_class, record_id)
            instance.reinit_with('attributes' => record)
          else
           instance = sti_class.allocate.init_with('attributes' => record)
            IdentityMap.add(instance)
          end
        else
          instance = sti_class.allocate.init_with('attributes' => record)
        end

        instance
      end

    end
  end

  module ConnectionAdapters
    class VerticaColumn < Column
      
    end
    
    class Vertica < AbstractAdapter
      ADAPTER_NAME = 'Vertica'.freeze

      def adapter_name #:nodoc:
        ADAPTER_NAME
      end

      def active?
        @connection.opened?
      end
      
      # Disconnects from the database if already connected, and establishes a
      # new connection with the database.
      def reconnect!
        @connection.reset_connection
      end
      def reset
        reconnect!
      end
      
      # Close the connection.
      def disconnect!
        @connection.close rescue nil
      end

      # return raw object
      def execute(sql, name=nil)
        log(sql,name) do
          if block_given?
            @connection = ::Vertica.connect(@connection.options)
            @connection.query(sql) {|row| yield row }
            @connection.close
          else
            @connection = ::Vertica.connect(@connection.options)
            results = @connection.query(sql)
            @connection.close
            results
          end
        end
      end

      def schema_name
        @schema ||= @connection.options[:schema]
      end

      def tables(name = nil) #:nodoc:
        sql = "SELECT * FROM tables WHERE table_schema = #{quote_column_name(schema_name)}"

        tables = []
        execute(sql, name) { |field| tables << field[:table_name] }
        tables
      end

      def columns(table_name, name = nil)#:nodoc:
        sql = "SELECT * FROM columns WHERE table_name = #{quote_column_name(table_name)}"

        columns = []
        execute(sql, name){ |field| columns << VerticaColumn.new(field[:column_name],field[:column_default],field[:data_type],field[:is_nullable])}
        columns
      end

      def select(sql, name = nil, binds = [])
        rows = []
        @connection = ::Vertica.connect(@connection.options)
        @connection.query(sql) {|row| rows << row }
        @connection.close
        rows
      end

      def primary_key(table)
        ''
      end

      ## QUOTING
      def quote_column_name(name) #:nodoc:
        "'#{name}'"
      end

      def quote_table_name(name) #:nodoc:
        if schema_name.blank?
          name
        else
          "#{schema_name}.#{name}"
        end
      end
      
    end
  end
end

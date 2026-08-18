require "rubygems"

require "simplecov"
SimpleCov.start do
  add_filter "test/"
end

require "minitest/reporters/turn_reporter"
Minitest::Reporters.use! Minitest::Reporters::TurnReporter.new

require "pry"
require "rr"
require "database_cleaner"
require "abstract_importer"
require "shoulda/context"
require "active_record"
require "support/mock_data_source"
require "support/mock_objects"
require "minitest/autorun"



system "psql -h localhost -U postgres -c 'create database abstract_importer_test'"

if ENV["DATABASE_URL"]
  ActiveRecord::Base.establish_connection(ENV["DATABASE_URL"])
else
  ActiveRecord::Base.establish_connection(
    adapter: "postgresql",
    host: "localhost",
    user: "postgres",
    database: "abstract_importer_test",
    verbosity: "quiet")
end

load File.join(File.dirname(__FILE__), "support", "schema.rb")



DatabaseCleaner.strategy = :transaction
$io = ENV['VERBOSE'] ? $stderr : File.open("/dev/null", "w")



class ActiveSupport::TestCase

  setup do
    DatabaseCleaner.start

    @data_source = MockDataSource.new
    @klass = Class.new(AbstractImporter::Base)
    @account = Account.create!
    @options = {}
  end

  teardown do
    DatabaseCleaner.clean
    @importer = nil
  end

protected

  attr_reader :account, :results, :data_source, :options

  def plan(&block)
    @klass.import(&block)
  end

  def depends_on(*args)
    @klass.depends_on(*args)
  end

  def import!
    @results = importer.perform!
  end

  def importer
    @importer ||= @klass.new(@account, @data_source, options.merge(io: $io))
  end

end

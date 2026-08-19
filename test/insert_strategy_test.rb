require "test_helper"
require "ostruct"


class InsertStrategyTest < ActiveSupport::TestCase

  setup do
    options.merge!(strategy: {students: :insert, perils: :insert})
  end



  context "with a simple data source" do
    setup do
      plan do |import|
        import.students
      end
    end

    should "import the records in batches" do
      mock.proxy.instance_of(ActiveRecord::Relation).insert_all(satisfy { |arg| arg.length == 3 }, returning: anything)
      import!
      assert_equal [456, 457, 458], account.students.pluck(:legacy_id)
    end

    should "report that it found 3 records" do
      summary = import!
      assert_equal 3, summary[:students].total
    end

    should "report that it created 3 records" do
      summary = import!
      assert_equal 3, summary[:students].created
    end
  end

  context "with a complex data source" do
    setup do
      plan do |import|
        import.students
        import.parents
      end
    end

    should "preserve mappings" do
      import!
      harry = account.students.find_by_name("Harry Potter")
      assert_equal ["James Potter", "Lily Potter"], harry.parents.pluck(:name)
    end

    should "preserve mappings even when a record was previously imported" do
      harry = account.students.create!(name: "Harry Potter", legacy_id: 456)
      import!
      assert_equal ["James Potter", "Lily Potter"], harry.parents.pluck(:name)
    end
  end

  context "With an empty data source" do
    setup do
      plan do |import|
        import.students
      end
      @data_source = OpenStruct.new
      @data_source.students = []
    end

    should "still be able to import" do
      assert_nothing_raised do
        import!
      end
    end
  end

  context "When records already exist" do
    setup do
      plan do |import|
        import.students
      end
      account.students.create!(name: "Ron Weasley", legacy_id: 457)
    end

    should "not import existing records twice" do
      import!
      assert_equal 3, account.students.count
    end
  end

  context "When the imported records belong to a parent polymorphically" do
    setup do
      @account = Owl.create!(name: "Pigwidgeon")
      plan do |import|
        import.abilities
      end
    end

    should "import records just fine" do
      pet = @account
      import!
      assert_equal [["Owl", pet.id]], Ability.pluck(:pet_type, :pet_id)
    end
  end

  context "When importing a has_many through: relationship" do
    setup do
      plan do |import|
        import.locations
        import.perils
      end
    end

    should "handle has_many, through: relations" do
      import!
      assert_equal 1, account.perils.count
    end
  end



  context "Given an ID generator" do
    setup do
      plan do |import|
        import.students
      end

      id = 0
      options.merge!(generate_id: -> { id += 1 })
    end

    should "insert the records with the specified IDs" do
      import!
      assert_equal [1, 2, 3], account.students.pluck(:id)
    end

    should "map the specified IDs to the legacy_ids" do
      import!
      assert_equal ({ 456 => 1, 457 => 2, 458 => 3 }), importer.id_map.get(:students)
    end
  end

end

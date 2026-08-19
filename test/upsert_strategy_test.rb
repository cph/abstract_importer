require "test_helper"


class UpsertStrategyTest < ActiveSupport::TestCase

  setup do
    options.merge!(strategy: {students: :upsert})
  end



  context "with a simple data source" do
    setup do
      plan do |import|
        import.students
      end
    end

    should "import the records in batches" do
      mock.proxy.instance_of(ActiveRecord::Relation).upsert_all(satisfy { |arg| arg.length == 3 }, unique_by: anything, returning: anything)
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

  context "When records already exist" do
    setup do
      plan do |import|
        import.students
      end
      account.students.create!(name: "Ronaldo Weasley", legacy_id: 457)
    end

    should "not import existing records twice" do
      import!
      assert_equal 3, account.students.count
    end

    should "update the existing record" do
      import!
      assert_equal ["Ron Weasley"], account.students.where(legacy_id: 457).pluck(:name)
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


end

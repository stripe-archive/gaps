require_relative '../_lib'

class GroupTest < Critic::Unit::Test
  include Configatron::Integrations::Minitest

  class FakeRequestor
    def get_group(group_email)
      {
        'description' => 'my description',
        'directMembersCount' => 4
      }
    end

    def update_group_description(group_email, description)
    end
  end

  class FakeLister
    def requestor
      FakeRequestor.new
    end
  end

  # TODO: dry up with FakeRequestor?
  def groupinfo(overrides={})
    {
      'description' => 'my description',
      'directMembersCount' => 4
    }.merge(overrides)
  end

  def a_group
    group = Gaps::DB::Group.new(
      group_email: 'email@example.com'
      )
    group.stubs(:save!).returns(nil)
    group
  end

  before do
    # TODO: create a mock lister?
    Gaps::DB::User.stubs(:lister).returns(FakeLister.new)
    configatron.unlock! do
      configatron.populate_group_settings = false
    end
  end

  describe 'description parsing' do
    it 'correctly parses descriptions with no config tag' do
      desc = 'my description'

      group = a_group
      group.update_config(groupinfo(
          'description' => desc
        ))
      assert_equal(desc, group.description)
      assert_equal({'category' => 'email'}, group.config)
      assert_equal('email', group.category)
    end

    it 'correctly parses descriptions with a config tag' do
      desc = %Q(my description\n{"this": "json", "category": "custom"})

      group = a_group
      group.update_config(groupinfo(
          'description' => desc
        ))
      assert_equal(desc, group.description)
      assert_equal({'this' => 'json', 'category' => 'custom'}, group.config)
      assert_equal('custom', group.category)
    end
  end

  describe '#move_category' do
    describe 'configatron.persist_config_to_group = true' do
      before do
        configatron.unlock! do
          configatron.persist_config_to_group = true
        end
      end

      it 'generates the correct description' do
        desc = 'my description'

        group = a_group
        group.update_config(groupinfo(
            'description' => desc
            ))
        group.move_category('custom')
        assert_equal(%Q(#{desc}\n{"category":"custom"}), group.description)
      end
    end
  end
end

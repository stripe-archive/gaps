require File.expand_path '../../spec_helper.rb', __FILE__

describe "Group" do
  let(:group){ Gaps::DB::Group.new }
  let(:user){ Gaps::DB::User.new }
  let(:requestor){ Gaps::Requestor.new(user) }
  let(:group_description){ "Everything under the sun." }
  let(:valid_json_description){ "#{group_description}\n#{JSON({category:'General'})}" }
  let(:invalid_json_description){ "#{group_description}\n{\"invalid\":\"json\"]" }

  context "#parse_config_from_description" do
    it "valid JSON hash" do
      group.description = valid_json_description
      expect(group.parse_config_from_description).to eq({"category" => "General"})
    end
    it "valid JSON, not hash" do
      group.description = "#{group_description}\n#{JSON(%w{general todos})}"
      expect(group.parse_config_from_description).to eq({})
    end
    it "invalid category tag" do
      group.description = invalid_json_description
      expect(group.parse_config_from_description).to eq({})
    end
  end

  context "#update_config" do
    before do
      configatron.unlock!
      configatron.populate_group_settings = false
      group.group_email = "talk@stripe.com"
    end
    it "sets category for valid category config" do
      group.description = valid_json_description
      group.update_config(user)

      expect(group.category).to eq("General")
    end

    it "guesses category using group_name for invalid category config" do
      group.description = invalid_json_description
      group.update_config(user)

      expect(group.category).to eq("talk")
    end
  end

  context "Updates Google Group Description when moving Category" do
    before do
      # Stub Mongodb, until we want test environments and test mongodbs
      allow(MongoMapper).to receive_messages(database: double.as_null_object)

      group.category = "oldcategory"
    end

    it "triggers google group update api call" do
      allow(Gaps::DB::User).to receive_message_chain(:lister, :requestor).and_return(requestor)
      expect_any_instance_of(Gaps::Requestor).to receive(:update_group_description)

      group.move_category("Misc")
    end
  end
end

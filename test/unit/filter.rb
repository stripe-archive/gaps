require_relative '../_lib'

class FilterTest < Critic::Unit::Test
  include Configatron::Integrations::Minitest

  class FakeFilter
    def generate_xml_properties
      1
    end
  end

  class FakeFilterSet
    def filters
      [FakeFilter.new]
    end
  end

  class FakeRequestor
  end

  def a_user
    @user ||= Gaps::DB::User.new
  end

  describe "#self.upload_to_gmail" do
    before do
      Gaps::Filter.stubs(:translate_to_gmail_britta_filters)     
      Gaps::Filter.stubs(:create_filterset).returns(FakeFilterSet.new)
    end

    it "does not retry on Google::APIClient::ServerError" do
      fake_requestor = FakeRequestor.new
      fake_requestor.stubs(:create_filter).at_most(1).raises(Google::APIClient::ServerError, "Backend Error")
      a_user.stubs(:requestor).returns(fake_requestor)

      Gaps::Filter.upload_to_gmail(a_user)
    end

    it "retries on StandardError" do
      Gaps::Filter.stubs(:sleep)

      fake_requestor = FakeRequestor.new
      fake_requestor.stubs(:create_filter).at_least(2).raises(StandardError, "Backend Error")
      a_user.stubs(:requestor).returns(fake_requestor)

      Gaps::Filter.upload_to_gmail(a_user)
    end
  end
end

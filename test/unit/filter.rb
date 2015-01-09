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
    attr_reader :create_filter_count

    def initialize(error)
      @error = error
      @create_filter_count = 0
    end

    def create_filter(fake_filter_text)
      @create_filter_count += 1
      raise @error
    end
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
      fake_requestor = FakeRequestor.new(Google::APIClient::ServerError.new("Backend Error"))
      a_user.stubs(:requestor).returns(fake_requestor)
      Gaps::Filter.upload_to_gmail(a_user)
      assert_equal 1, fake_requestor.create_filter_count
    end

    it "retries on StandardError" do
      Gaps::Filter.stubs(:sleep) # sleeps during retry
      fake_requestor = FakeRequestor.new(StandardError.new)
      a_user.stubs(:requestor).returns(fake_requestor)
      Gaps::Filter.upload_to_gmail(a_user)
      assert fake_requestor.create_filter_count > 2
    end
  end
end

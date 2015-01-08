require_relative '../_lib'

class FilterTest < Critic::Unit::Test
  include Configatron::Integrations::Minitest

  def a_user
    @user ||= Gaps::DB::User.new
  end

  describe "#self.upload_to_gmail" do
    before do
      Gaps::Filter.stubs(:translate_to_gmail_britta_filters)

      filter = mock()
      filter.stubs(:generate_xml_properties).returns(1)

      filterset = mock()
      filterset.stubs(:filters).returns([filter])
      
      Gaps::Filter.stubs(:create_filterset).returns(filterset)
    end
    
    it "does not retry on Google::APIClient::ServerError" do
      fake_requestor = mock()
      fake_requestor.stubs(:create_filter).at_most(1).raises(Google::APIClient::ServerError, "Backend Error")
      a_user.stubs(:requestor).returns(fake_requestor)

      Gaps::Filter.upload_to_gmail(a_user)
    end

    it "retries on StandardError" do
      Gaps::Filter.stubs(:sleep)

      fake_requestor = mock()
      fake_requestor.stubs(:create_filter).at_least(2).raises(StandardError, "Backend Error")
      a_user.stubs(:requestor).returns(fake_requestor)

      Gaps::Filter.upload_to_gmail(a_user)
    end
  end
end
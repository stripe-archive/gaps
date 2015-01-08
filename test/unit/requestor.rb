require_relative '../_lib'

class RequestorTest < Critic::Unit::Test
  include Configatron::Integrations::Minitest

  class FakeGoogleAPIClient
  end

  class FakeResponse
    def data
      ""
    end
  end

  def get_requestor_client
    requestor = Gaps::Requestor.new(Gaps::DB::User.new)
    client = FakeGoogleAPIClient.new
    requestor.stubs(:get_client).returns(client)

    [requestor, client]
  end

  describe "handle Google::APIClient::ServerError (Backend Error)" do
    it "default to retry" do
      requestor, client = get_requestor_client

      client.stubs(:execute!).at_least(2).raises(Google::APIClient::ServerError, "Backend Error").then.returns(FakeResponse.new)
      requestor.send(:request, "", "", {uri:''})
    end

    it "does not retry if opt[:noretry]" do
      requestor, client = get_requestor_client

      client.stubs(:execute!).at_most(1).raises(Google::APIClient::ServerError, "Backend Error").then.returns(FakeResponse.new)

      assert_raises(Google::APIClient::ServerError) {
        requestor.send(:request, "", "", {uri:'', noretry: true})
      }
    end
  end
end